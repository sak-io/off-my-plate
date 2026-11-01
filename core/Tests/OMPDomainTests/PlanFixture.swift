import Foundation
import OMPDomain
import Testing

/// Small plans for the lifecycle, content-hash and diff tests (T13).
enum PlanFixture {
    static let adult: MemberID = "m-adult"
    static let child: MemberID = "m-child"

    static let defaultServings = [
        MealServing(memberId: adult, portion: 1.0),
        MealServing(memberId: child, portion: 0.6),
    ]

    static func meal(
        _ id: PlannedMealID,
        day: Int = 0,
        slot: MealSlot = .dinner,
        recipe: RecipeID? = "dal-tadka",
        locked: Bool = false,
        servings: [MealServing] = PlanFixture.defaultServings
    ) -> PlannedMeal {
        PlannedMeal(
            id: id, date: Sample.monday.adding(days: day), slot: slot, recipeId: recipe,
            emptyReason: recipe == nil ? .noSafeRecipe : nil, locked: locked, servings: servings)
    }

    static let standardMeals: [PlannedMeal] = [
        meal("meal-1", day: 0, slot: .dinner, recipe: "dal-tadka"),
        meal("meal-2", day: 1, slot: .lunch, recipe: "rajma-chawal"),
        meal("meal-3", day: 2, slot: .dinner, recipe: "palak-paneer", locked: true),
    ]

    static func draft(
        id: MealPlanID = "plan-1", series: PlanSeriesID = "series-1", meals: [PlannedMeal] = PlanFixture.standardMeals
    ) -> MealPlan {
        MealPlan(
            id: id, seriesId: series, weekStart: Sample.monday, meals: meals, contentVersion: "seed-1",
            createdAt: Sample.now)
    }

    static func report(for plan: MealPlan, violations: [Violation] = []) -> ValidationReport {
        ValidationReport(planId: plan.id, contentHash: plan.contentHash, violations: violations)
    }

    /// `plan` approved through the lifecycle (so the stored hash is genuine).
    static func approved(
        _ plan: MealPlan = PlanFixture.draft(), replacing previous: MealPlan? = nil
    ) throws(PlanLifecycleError) -> MealPlan {
        try PlanLifecycle.approve(
            plan, replacing: previous, confirmation: UserConfirmation(), validation: report(for: plan),
            now: Sample.later
        ).approved
    }

    /// The error a lifecycle call throws, or `nil` if it succeeds.
    /// Untyped on purpose: closures written inline (also inside `#expect`) infer `any Error`,
    /// which cannot convert to a typed-throws parameter. Any other error is recorded as an issue.
    static func error<T>(_ body: () throws -> T) -> PlanLifecycleError? {
        do {
            _ = try body()
            return nil
        } catch let error as PlanLifecycleError {
            return error
        } catch {
            Issue.record("unexpected error: \(error)")
            return nil
        }
    }
}
