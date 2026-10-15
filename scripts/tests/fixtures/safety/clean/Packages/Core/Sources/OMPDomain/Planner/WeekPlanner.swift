import Foundation

public struct PlannerSeed {
    public var value: UInt64
    // public static func notAFunction(): comments are ignored
    public static func derived(text: String) -> PlannerSeed {
        PlannerSeed(value: 1)
    }
}

public enum WeekPlanner {
    /// Generates a draft. `public func helper()` in a doc comment is ignored.
    public static func generateWeek(
        clearance: SafetyClearance,
        household: Household,
        now: Date
    ) throws(PlannerError) -> MealPlan {
        fatalError()
    }

    public static func regenerate(_ plan: MealPlan, clearance: SafetyClearance) -> [PlannedMeal] { [] }

    static func internalHelper(_ x: Int) -> Int { x }

    private static func select(adjustment: (Int) -> Int = { _ in 0 }) -> Int { 0 }
}
