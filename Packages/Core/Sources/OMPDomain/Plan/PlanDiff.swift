import Foundation

/// What changed between an approved plan and its draft revision, for the S-13 approval diff
/// sheet ("Was" / "Now") and the "Changed" rows (AC-5.4, ADR 0008).
///
/// Meals are paired by id first (revisions keep meal ids), then remaining meals by date and
/// slot in id order (a regenerate may create new ids). Only food-relevant fields are compared:
/// recipe, servings and lock. Cooked state, explanations and `blockedBySafety` are ignored.
public struct PlanDiff: Sendable, Hashable {
    /// One kind of change to a slot.
    public enum ChangeKind: String, CaseIterable, Codable, Sendable, Hashable {
        /// A different recipe now, or a recipe where the slot was empty.
        case swapped
        /// A slot that did not exist before (for example a new lunchbox).
        case added
        /// The slot had a recipe and now has none.
        case emptied
        /// A slot that no longer exists.
        case removed
        /// Members, portions or not-eating flags differ.
        case servingsChanged
        /// Locked or unlocked. Not listed on S-13, because it doesn't change the food.
        case lockChanged
    }

    /// One changed slot. `was` is `nil` for `.added`; `now` is `nil` for `.removed`.
    public struct Change: Sendable, Hashable {
        public let date: LocalDate
        public let slot: MealSlot
        public let was: PlannedMeal?
        public let now: PlannedMeal?
        /// Every kind that applies, in `ChangeKind.allCases` order.
        public let kinds: [ChangeKind]

        public init(date: LocalDate, slot: MealSlot, was: PlannedMeal?, now: PlannedMeal?, kinds: [ChangeKind]) {
            self.date = date
            self.slot = slot
            self.was = was
            self.now = now
            self.kinds = kinds
        }

        /// Whether S-13 lists this change: anything other than a lock-only change.
        public var isListed: Bool {
            kinds.contains { $0 != .lockChanged }
        }
    }

    /// Every change, ordered by date, then slot (`MealSlot.allCases` order), then meal id.
    public let changes: [Change]

    /// The changes S-13 lists (lock-only changes omitted). Its count is the "{n}" in
    /// "Approve {n} changes?".
    public var listedChanges: [Change] {
        changes.filter(\.isListed)
    }

    /// No change at all.
    public var isEmpty: Bool {
        changes.isEmpty
    }

    /// The diff from `old` (usually the approved plan) to `new` (its draft revision).
    public init(from old: MealPlan, to new: MealPlan) {
        var unmatchedOld = old.meals.sorted(by: PlanDiff.slotOrder)
        var unmatchedNew = new.meals.sorted(by: PlanDiff.slotOrder)
        var pairs: [MealPair] = []

        // 1. Same meal id.
        var index = 0
        while index < unmatchedNew.count {
            let candidate = unmatchedNew[index]
            if let oldIndex = unmatchedOld.firstIndex(where: { $0.id == candidate.id }) {
                pairs.append(MealPair(was: unmatchedOld.remove(at: oldIndex), now: candidate))
                unmatchedNew.remove(at: index)
            } else {
                index += 1
            }
        }
        // 2. Same date and slot.
        index = 0
        while index < unmatchedNew.count {
            let candidate = unmatchedNew[index]
            if let oldIndex = unmatchedOld.firstIndex(where: { $0.date == candidate.date && $0.slot == candidate.slot }) {
                pairs.append(MealPair(was: unmatchedOld.remove(at: oldIndex), now: candidate))
                unmatchedNew.remove(at: index)
            } else {
                index += 1
            }
        }
        for meal in unmatchedOld {
            pairs.append(MealPair(was: meal, now: nil))
        }
        for meal in unmatchedNew {
            pairs.append(MealPair(was: nil, now: meal))
        }

        var changes: [Change] = []
        for pair in pairs {
            let kinds = PlanDiff.kinds(was: pair.was, now: pair.now)
            guard !kinds.isEmpty, let reference = pair.now ?? pair.was else { continue }
            changes.append(Change(date: reference.date, slot: reference.slot, was: pair.was, now: pair.now, kinds: kinds))
        }
        self.changes = changes.sorted { lhs, rhs in
            let left = lhs.now ?? lhs.was
            let right = rhs.now ?? rhs.was
            switch (left, right) {
            case let (left?, right?): return PlanDiff.slotOrder(left, right)
            default: return false
            }
        }
    }

    private struct MealPair {
        let was: PlannedMeal?
        let now: PlannedMeal?
    }

    private static func kinds(was: PlannedMeal?, now: PlannedMeal?) -> [ChangeKind] {
        guard let was else { return now == nil ? [] : [.added] }
        guard let now else { return [.removed] }
        var kinds: Set<ChangeKind> = []
        if was.recipeId != now.recipeId {
            kinds.insert(now.recipeId == nil ? .emptied : .swapped)
        }
        if canonicalServings(was) != canonicalServings(now) {
            kinds.insert(.servingsChanged)
        }
        if was.locked != now.locked {
            kinds.insert(.lockChanged)
        }
        return ChangeKind.allCases.filter { kinds.contains($0) }
    }

    /// Servings in canonical order, so a reordering alone is not a change.
    private static func canonicalServings(_ meal: PlannedMeal) -> [String] {
        meal.servings.map(PlanCanonicalEncoding.encode(serving:)).sorted(by: PlanCanonicalEncoding.utf8Precedes)
    }

    private static func slotOrder(_ lhs: PlannedMeal, _ rhs: PlannedMeal) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        if lhs.slot != rhs.slot { return slotIndex(lhs.slot) < slotIndex(rhs.slot) }
        return lhs.id < rhs.id
    }

    private static func slotIndex(_ slot: MealSlot) -> Int {
        MealSlot.allCases.firstIndex(of: slot) ?? 0
    }
}
