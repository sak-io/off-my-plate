import Foundation
import Observation
import OMPCapture
import OMPDomain
import OMPServices

/// What the add/edit form starts with.
public struct PantryFormPrefill: Sendable, Hashable {
    public var name: String
    /// What the user said, shown as a caption (C-133).
    public var transcript: String?

    public init(name: String, transcript: String? = nil) {
        self.name = name
        self.transcript = transcript
    }
}

/// A sheet the Pantry tab presents.
public enum PantrySheet: Hashable, Identifiable, Sendable {
    /// S-21 with an empty form, or prefilled from voice ("Add it by hand").
    case add(PantryFormPrefill?)
    /// S-21 for an existing item (also "Match it").
    case edit(PantryItemID)
    /// S-22 listening and confirm; also shows S-23 when voice cannot run.
    case speak

    public var id: String {
        switch self {
        case .add(let prefill): return "add:\(prefill?.name ?? "")"
        case .edit(let item): return "edit:\(item.rawValue)"
        case .speak: return "speak"
        }
    }
}

/// One pantry row (S-20).
public struct PantryRow: Identifiable, Hashable, Sendable {
    public let id: PantryItemID
    /// The ingredient name, or the typed text for an unresolved item.
    public let name: String
    public let amountText: String
    /// "Use by Thu", "Past use-by date" or nil.
    public let useByText: String?
    /// Not re-confirmed for a while (AC-9.7, C-120).
    public let isStale: Bool
    /// Free text that is not matched to an ingredient (AC-9.2, C-121).
    public let isUnresolved: Bool
    public let location: StorageLocation
}

/// The rows of one storage location.
public struct PantryGroup: Identifiable, Hashable, Sendable {
    public let location: StorageLocation
    public let rows: [PantryRow]
    public var id: String { location.rawValue }
}

/// The Pantry tab's state and actions (task T24; screen S-20). Every change goes through the
/// `PantryBackend` (the services), never to a repository.
@MainActor
@Observable
public final class PantryViewModel {
    public enum Phase: Hashable, Sendable {
        case loading
        case loaded
        /// The pantry could not be read (C-095).
        case failed
    }

    private let backend: (any PantryBackend)?
    private let clock: any DomainClock
    /// The speech adapter; nil when the composition root wired none.
    public let speech: (any SpeechCapture)?

    public private(set) var phase: Phase = .loading
    public private(set) var items: [PantryItem] = []
    /// C-095 inline card text, or nil.
    public private(set) var errorMessage: String?

    public var searchText = ""
    public var sheet: PantrySheet?
    /// A sheet to present once the current one has finished dismissing.
    public private(set) var pendingSheet: PantrySheet?
    public var toast: String?

    public init(backend: (any PantryBackend)?, clock: any DomainClock, speech: (any SpeechCapture)?) {
        self.backend = backend
        self.clock = clock
        self.speech = speech
    }

    var pantryBackend: (any PantryBackend)? { backend }
    var domainClock: any DomainClock { clock }

    // MARK: Derived state

    public var isEmpty: Bool { items.isEmpty }

    public var isSearching: Bool { !trimmedSearch.isEmpty }

    private var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// True when the pantry has items but none match the search (C-124).
    public var hasNoSearchResults: Bool { phase == .loaded && !items.isEmpty && isSearching && groups.isEmpty }

    public var noResultsText: String { PantryCopy.noResults(trimmedSearch) }

    /// Fridge, freezer, shelf: non-empty groups only, rows by name.
    public var groups: [PantryGroup] {
        let query = trimmedSearch
        let rows = items.map(row(for:)).filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        return [StorageLocation.fridge, .freezer, .shelf].compactMap { (location: StorageLocation) -> PantryGroup? in
            let inLocation = rows.filter { $0.location == location }.sorted { lhs, rhs in
                let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                return order != .orderedSame ? order == .orderedAscending : lhs.id < rhs.id
            }
            return inLocation.isEmpty ? nil : PantryGroup(location: location, rows: inLocation)
        }
    }

    public func item(_ id: PantryItemID) -> PantryItem? { items.first { $0.id == id } }

    public func displayName(of item: PantryItem) -> String {
        switch item.item {
        case .ingredient(let id): return backend?.defaults(for: id)?.name ?? id.rawValue
        case .freeText(let text): return text
        }
    }

    func row(for item: PantryItem) -> PantryRow {
        let confidence = item.confidence(now: clock.now, timeZone: clock.timeZone)
        let unresolved = item.item.ingredientId == nil
        return PantryRow(
            id: item.id, name: displayName(of: item), amountText: PantryFormat.amount(item.quantity, item.unit),
            useByText: item.expiresOn.map(useByText(for:)), isStale: confidence == .low, isUnresolved: unresolved,
            location: item.location)
    }

    /// "Use by Thursday" within the coming week, else "Use by 18 Oct"; "Past use-by date" when over.
    func useByText(for day: LocalDate) -> String {
        let today = clock.today
        if day < today { return PantryCopy.pastUseBy }
        if day.daysSince(today) <= 6 {
            return PantryCopy.useByWeekday(PantryFormat.weekdayName(day, in: clock.timeZone))
        }
        return PantryCopy.useByDate(PantryFormat.shortDate(day, in: clock.timeZone))
    }

    // MARK: Loading

    public func load() async {
        guard let backend else {
            phase = .failed
            errorMessage = PantryCopy.loadFailed
            return
        }
        do {
            items = try await backend.items()
            phase = .loaded
            errorMessage = nil
        } catch {
            record(error)
            if phase != .loaded { phase = .failed }
            errorMessage = PantryCopy.loadFailed
        }
    }

    public func retry() async {
        phase = .loading
        await load()
    }

    // MARK: Actions

    /// "Still have it": resets the item's confidence (AC-9.7).
    public func reconfirm(_ id: PantryItemID) async {
        await change { try await $0.reconfirm(id) }
    }

    public func delete(_ id: PantryItemID) async {
        await change { try await $0.delete(id) }
    }

    private func change(_ action: (any PantryBackend) async throws -> Void) async {
        guard let backend else { return }
        do {
            try await action(backend)
            errorMessage = nil
        } catch {
            record(error)
            errorMessage = PantryCopy.saveFailed
        }
        // Reload either way: the service may have changed or refused, and the list must match.
        do {
            items = try await backend.items()
        } catch {
            record(error)
        }
    }

    // MARK: Sheets

    public func openAdd() { sheet = .add(nil) }

    public func openEdit(_ id: PantryItemID) {
        guard item(id) != nil else { return }
        sheet = .edit(id)
    }

    /// The mic button (AC-9.4, AC-9.5): always opens the speak sheet, which explains when voice
    /// cannot run (S-23), so the button never silently does nothing.
    public func openSpeak() { sheet = .speak }

    /// Closes the current sheet and presents `next` once it is gone ("Type instead", "Add it
    /// by hand"): replacing a sheet's item while it shows is unreliable.
    public func replaceSheet(with next: PantrySheet) {
        pendingSheet = next
        sheet = nil
    }

    /// Called when a sheet finished dismissing.
    public func sheetDismissed() {
        if let next = pendingSheet {
            pendingSheet = nil
            sheet = next
        }
    }

    /// Reloads after a sheet saved something.
    public func sheetChangedPantry() async {
        await change { _ in }
    }

    private func record(_ error: any Error) {
        let kind = OMPLog.errorKind(error)
        OMPLog.app.error("Pantry operation failed: \(kind, privacy: .public)")
    }
}
