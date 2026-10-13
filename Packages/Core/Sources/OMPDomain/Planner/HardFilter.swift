/// The planner's hard filter (plan section 5 step 3; AC-4.1, AC-4.3, AC-6.3, AC-7.2).
///
/// Uses the same semantics as the independent `PlanValidator`:
/// - the rules that constrain a slot are the hard rules covering each eater (their own plus
///   household scope); members marked `notEating` do not constrain it (AC-6.3);
/// - a recipe is excluded if its contained tags (ingredient tags ∪ mayContain, all lines
///   including optional ones) intersect any eater's excluded tags;
/// - a recipe with an unverified ingredient is excluded if any eater has any hard rule (AC-4.3);
/// - a recipe with an ingredient missing from the taxonomy is always excluded (fail closed).
/// Rules come only from the clearance snapshot, never from a live household.
public enum HardFilter {
    /// Whether `entry` may be cooked for `slot` at all: its meal type fits, and a lunchbox slot
    /// takes only `lunchboxSuitable` recipes (AC-7.2).
    public static func fits(_ entry: PlannerLibrary.Entry, slot: MealSlot) -> Bool {
        if let mealType = slot.mealType {
            return entry.mealTypes.contains(mealType)
        }
        return entry.lunchboxSuitable
    }

    /// Whether `entry` is safe for every member in `eaterIDs` under `clearance`'s rules.
    public static func isSafe(
        _ entry: PlannerLibrary.Entry, eaterIDs: [MemberID], clearance: SafetyClearance
    ) -> Bool {
        if entry.hasUnknownIngredient {
            return false
        }
        for eater in eaterIDs {
            let hardRules = clearance.rules(covering: eater).filter { $0.kind == .hard }
            if hardRules.isEmpty {
                continue
            }
            if entry.hasUnverifiedIngredient {
                return false
            }
            for rule in hardRules where !rule.excludedTags.isDisjoint(with: entry.containedTags) {
                return false
            }
        }
        return true
    }

    /// The recipes that fit `slot` and are safe for its eaters, in id order.
    public static func candidates(
        for slot: PlannerSlot, library: PlannerLibrary, clearance: SafetyClearance
    ) -> [PlannerLibrary.Entry] {
        candidates(for: slot.slot, eaterIDs: slot.eaterIDs, library: library, clearance: clearance)
    }

    /// The recipes that fit `slot` and are safe for `eaterIDs`, in id order.
    public static func candidates(
        for slot: MealSlot, eaterIDs: [MemberID], library: PlannerLibrary, clearance: SafetyClearance
    ) -> [PlannerLibrary.Entry] {
        library.entries.filter { entry in
            fits(entry, slot: slot) && isSafe(entry, eaterIDs: eaterIDs, clearance: clearance)
        }
    }
}
