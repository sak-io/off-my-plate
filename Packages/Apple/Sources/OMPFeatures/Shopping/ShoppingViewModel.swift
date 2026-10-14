import Foundation
import Observation
import OMPDomain

/// One section of the list: "Check you have" first, then one per aisle that has items (AC-10.3,
/// AC-10.4).
public struct ShoppingSection: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case checkYouHave
        case aisle(Aisle)
    }

    public let kind: Kind
    public let items: [ShoppingItem]

    public var id: String {
        switch kind {
        case .checkYouHave: return "checkYouHave"
        case .aisle(let aisle): return aisle.rawValue
        }
    }

    var title: String {
        switch kind {
        case .checkYouHave: return ShoppingCopy.checkYouHave
        case .aisle(let aisle): return ShoppingCopy.aisle(aisle)
        }
    }

    var headerID: String {
        switch kind {
        case .checkYouHave: return AccessibilityID.shoppingCheckSection
        case .aisle(let aisle): return AccessibilityID.shoppingSection(aisle.rawValue)
        }
    }
}

/// The List tab's state and actions (task T25; screen S-25). Every change goes through the
/// `ShoppingBackend` (the shopping service); this type never writes the list itself, except for
/// the optimistic check mark that is reloaded from the service straight after.
@MainActor
@Observable
public final class ShoppingViewModel {
    public enum Phase: Hashable, Sendable {
        case loading
        case loaded
        /// The first load failed (C-095).
        case failed
    }

    private let backend: (any ShoppingBackend)?
    private let clock: any DomainClock

    public private(set) var phase: Phase = .loading
    public private(set) var items: [ShoppingItem] = []
    public private(set) var info: ShoppingPlanInfo = .none
    /// The plain-text list for the Share Sheet (AC-10.7).
    public private(set) var shareText = ""
    /// An add or Bought everything is running.
    public private(set) var isBusy = false
    /// C-095 inline card is showing.
    public private(set) var hasError = false

    public var newItemName = ""
    public var isConfirmingBought = false

    public init(backend: (any ShoppingBackend)?, clock: any DomainClock) {
        self.backend = backend
        self.clock = clock
    }

    // MARK: Derived state

    public var hasApprovedPlan: Bool { info.approvedRange != nil }

    /// C-140: nothing is approved, so the list holds only manual and imported items.
    public var showsNoPlan: Bool { phase == .loaded && !hasApprovedPlan }

    /// C-141: an approved plan and nothing left to buy or check.
    public var showsNothingToBuy: Bool { phase == .loaded && hasApprovedPlan && items.isEmpty }

    /// C-142.
    public var showsPendingChanges: Bool { phase == .loaded && info.hasPendingChanges }

    public var checkedCount: Int { items.filter(\.checkedOff).count }

    /// Bought everything is enabled when at least one item is checked.
    public var canBuyEverything: Bool { checkedCount > 0 && !isBusy }

    public var canAdd: Bool { !trimmedNewName.isEmpty && !isBusy }

    private var trimmedNewName: String { newItemName.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var sections: [ShoppingSection] {
        var result: [ShoppingSection] = []
        let check = items.filter { $0.group == .checkYouHave }
        if !check.isEmpty {
            result.append(ShoppingSection(kind: .checkYouHave, items: Self.sorted(check)))
        }
        for aisle in Aisle.allCases {
            let inAisle = items.filter { $0.group == .toBuy && $0.aisle == aisle }
            if !inAisle.isEmpty {
                result.append(ShoppingSection(kind: .aisle(aisle), items: Self.sorted(inAisle)))
            }
        }
        return result
    }

    private static func sorted(_ list: [ShoppingItem]) -> [ShoppingItem] {
        list.sorted { lhs, rhs in
            let order = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            return order != .orderedSame ? order == .orderedAscending : lhs.id.rawValue < rhs.id.rawValue
        }
    }

    /// "For Mon 12 – Sun 18 Oct", or nil without an approved plan.
    public var rangeText: String? {
        guard let range = info.approvedRange else { return nil }
        let text = "\(format(range.lowerBound, withMonth: false)) – \(format(range.upperBound, withMonth: true))"
        return ShoppingCopy.forRange(text)
    }

    /// "500 g", "2", or nil for a line without an amount.
    public func quantityText(_ item: ShoppingItem) -> String? {
        guard let quantity = item.quantity, let unit = item.unit, unit.isQuantified else { return nil }
        let amount = Self.amount(quantity)
        return unit == .piece ? amount : amount + " " + unit.rawValue
    }

    /// "Onion 500 g": the row's text and its VoiceOver label.
    public func lineText(_ item: ShoppingItem) -> String {
        guard let quantity = quantityText(item) else { return item.name }
        return item.name + " " + quantity
    }

    /// "from Notes" for imported items.
    public func originText(_ item: ShoppingItem) -> String? {
        switch item.origin {
        case .notesImport: return ShoppingCopy.fromNotes
        case .plan, .manual: return nil
        }
    }

    /// At most two decimals, no trailing zeros. Rounded here only for display.
    static func amount(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0" }
        let hundredths = Int((min(value, 1e9) * 100).rounded())
        let whole = hundredths / 100
        let fraction = hundredths % 100
        if fraction == 0 { return String(whole) }
        var digits = fraction < 10 ? "0" + String(fraction) : String(fraction)
        if digits.hasSuffix("0") { digits.removeLast() }
        return String(whole) + "." + digits
    }

    private func format(_ date: LocalDate, withMonth: Bool) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = clock.timeZone
        let parts = DateComponents(
            calendar: calendar, timeZone: clock.timeZone, year: date.year, month: date.month, day: date.day, hour: 12)
        guard let instant = calendar.date(from: parts) else { return date.isoString }
        let base = Date.FormatStyle(date: .omitted, time: .omitted, calendar: calendar, timeZone: clock.timeZone)
        let style = withMonth ? base.weekday(.abbreviated).day().month(.abbreviated) : base.weekday(.abbreviated).day()
        return instant.formatted(style)
    }

    // MARK: Loading

    /// Re-derives the list from the approved plan and the pantry, then loads it. Call when the
    /// tab appears (AC-10.1).
    public func load() async {
        guard let backend else {
            phase = .failed
            return
        }
        do {
            let list = try await backend.refresh()
            try await apply(list, backend: backend)
            hasError = false
        } catch {
            fail(error)
            if phase == .loading { phase = .failed }
        }
    }

    public func retry() async {
        phase = .loading
        await load()
    }

    /// Reads the list as stored (no re-derivation) after a change.
    private func reload(backend: any ShoppingBackend) async {
        do {
            let list = try await backend.items()
            try await apply(list, backend: backend)
        } catch {
            fail(error)
        }
    }

    private func apply(_ list: [ShoppingItem], backend: any ShoppingBackend) async throws {
        let planInfo = try await backend.planInfo()
        let text = try await backend.shareText()
        items = list
        info = planInfo
        shareText = text
        phase = .loaded
    }

    private func fail(_ error: any Error) {
        let kind = OMPLog.errorKind(error)
        OMPLog.app.error("Shopping list failed: \(kind, privacy: .public)")
        hasError = true
    }

    // MARK: Actions

    /// Adds the typed text as a manual item (AC-10.5) and clears the field.
    public func addItem() async {
        guard let backend, canAdd else { return }
        let name = trimmedNewName
        isBusy = true
        defer { isBusy = false }
        do {
            try await backend.addManual(name: name)
            newItemName = ""
            hasError = false
            await reload(backend: backend)
        } catch {
            fail(error)
        }
    }

    /// Checks an item off or back on. The row changes at once; the service result is reloaded.
    public func setChecked(_ item: ShoppingItem, _ checked: Bool) async {
        guard let backend, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].checkedOff = checked
        do {
            try await backend.setChecked(item.id, checked)
            hasError = false
            await reload(backend: backend)
        } catch {
            fail(error)
            await reload(backend: backend)
        }
    }

    public func toggle(_ item: ShoppingItem) async {
        await setChecked(item, !item.checkedOff)
    }

    /// Removes a manual or imported item; plan lines follow the plan and cannot be removed.
    public func remove(_ item: ShoppingItem) async {
        guard let backend, item.origin != .plan else { return }
        do {
            try await backend.remove(item.id)
            hasError = false
        } catch {
            fail(error)
        }
        await reload(backend: backend)
    }

    /// Menu: "Clear checked items" takes every check mark off again (nothing is deleted).
    public func clearChecked() async {
        guard let backend else { return }
        for item in items where item.checkedOff {
            do {
                try await backend.setChecked(item.id, false)
            } catch {
                fail(error)
            }
        }
        await reload(backend: backend)
    }

    /// Asks before moving the checked items into the pantry (C-143).
    public func requestBoughtEverything() {
        guard canBuyEverything else { return }
        isConfirmingBought = true
    }

    /// AC-10.6: checked items go to the pantry and leave the list.
    public func confirmBoughtEverything() async {
        isConfirmingBought = false
        guard let backend, checkedCount > 0, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await backend.boughtEverything()
            hasError = false
        } catch {
            fail(error)
        }
        await reload(backend: backend)
    }
}
