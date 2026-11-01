import Foundation
import Observation
import OMPDomain
import OMPServices

/// The add / edit item form (S-21; AC-9.1, AC-9.2). Saving goes through the services, which
/// resolve the typed name to an ingredient or keep it as free text (AC-9.2).
@MainActor
@Observable
public final class PantryFormModel {
    public enum Mode: Hashable, Sendable {
        case add
        case edit(PantryItemID)
    }

    private let backend: any PantryBackend
    private let timeZone: TimeZone
    public let mode: Mode
    /// "You said: ..." caption of a form prefilled from voice (C-133).
    public let transcript: String?

    public var name: String
    /// The ingredient picked from the suggestions, else nil (the service then resolves the name).
    public private(set) var ingredientId: IngredientID?
    public var amountText: String
    public var unit: MeasureUnit
    public var location: StorageLocation
    public var hasUseBy: Bool
    public var useBy: Date

    public private(set) var suggestions: [IngredientResolver.Candidate] = []
    public private(set) var isSaving = false
    /// The user chose "Add "x" as typed": the name stays free text until it is matched.
    public private(set) var isKeptAsTyped = false
    /// C-095 text, or nil.
    public private(set) var errorMessage: String?

    /// - Parameters:
    ///   - item: the item being edited, or nil for a new one.
    ///   - displayName: the name to show for `item`.
    ///   - prefill: the voice leftover to start from (add mode).
    public init(
        backend: any PantryBackend, clock: any DomainClock, item: PantryItem? = nil, displayName: String = "",
        prefill: PantryFormPrefill? = nil
    ) {
        self.backend = backend
        self.timeZone = clock.timeZone
        if let item {
            mode = .edit(item.id)
            transcript = nil
            name = displayName
            ingredientId = item.item.ingredientId
            amountText = PantryFormat.number(item.quantity)
            unit = item.unit
            location = item.location
            hasUseBy = item.expiresOn != nil
            useBy = PantryFormat.date(for: item.expiresOn ?? clock.today, in: clock.timeZone)
        } else {
            mode = .add
            transcript = prefill?.transcript
            name = prefill?.name ?? ""
            ingredientId = nil
            amountText = ""
            unit = .gram
            location = .shelf
            hasUseBy = false
            useBy = PantryFormat.date(for: clock.today.adding(days: 7), in: clock.timeZone)
        }
        refreshSuggestions()
    }

    // MARK: Derived

    public var isEditing: Bool { mode != .add }

    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var amount: Double? { PantryFormat.parseAmount(amountText) }

    /// Save is off until a name and a positive amount are present.
    public var canSave: Bool {
        guard !trimmedName.isEmpty, let amount, amount > 0 else { return false }
        return !isSaving
    }

    public var units: [MeasureUnit] { PantryFormat.units(including: unit) }

    /// Offer "Add "x" as typed" while the name is not an exact match of a suggestion (C-125).
    public var offersAddAsTyped: Bool {
        guard ingredientId == nil, !isKeptAsTyped, !trimmedName.isEmpty else { return false }
        return !suggestions.contains { $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }
    }

    // MARK: Suggestions

    /// The name field's setter. Typing again drops the picked ingredient; the service resolves
    /// the new text on save. (Not a `didSet`: `pick` sets `name` without dropping the pick.)
    public func typeName(_ text: String) {
        name = text
        ingredientId = nil
        isKeptAsTyped = false
        refreshSuggestions()
    }

    private func refreshSuggestions() {
        let query = trimmedName
        suggestions = query.isEmpty || ingredientId != nil ? [] : backend.searchIngredients(query)
    }

    /// Picks a suggestion: the name becomes the ingredient's, and a new item takes its default
    /// unit and place (the user can still change them).
    public func pick(_ candidate: IngredientResolver.Candidate) {
        name = candidate.name
        ingredientId = candidate.ingredientId
        suggestions = []
        if mode == .add, let defaults = backend.defaults(for: candidate.ingredientId) {
            unit = defaults.unit
            location = defaults.location
        }
    }

    /// "Add "x" as typed": keeps the text as free text.
    public func keepAsTyped() {
        ingredientId = nil
        isKeptAsTyped = true
        suggestions = []
    }

    // MARK: Save and delete

    private var input: PantryItemInput? {
        guard let amount, !trimmedName.isEmpty else { return nil }
        var expires: LocalDate?
        if hasUseBy {
            expires = LocalDate(useBy, in: timeZone)
        }
        return PantryItemInput(
            name: trimmedName, ingredientId: ingredientId, quantity: amount, unit: unit, location: location,
            expiresOn: expires)
    }

    /// Saves through the service. Returns true on success (the sheet then closes).
    public func save() async -> Bool {
        guard canSave, let input else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            switch mode {
            case .add: _ = try await backend.add(input)
            case .edit(let id): _ = try await backend.update(id, with: input)
            }
            errorMessage = nil
            return true
        } catch {
            record(error)
            errorMessage = PantryCopy.saveFailed
            return false
        }
    }

    /// Deletes the edited item. Returns true on success.
    public func delete() async -> Bool {
        guard case .edit(let id) = mode, !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await backend.delete(id)
            errorMessage = nil
            return true
        } catch {
            record(error)
            errorMessage = PantryCopy.saveFailed
            return false
        }
    }

    private func record(_ error: any Error) {
        let kind = OMPLog.errorKind(error)
        OMPLog.app.error("Pantry form failed: \(kind, privacy: .public)")
    }
}
