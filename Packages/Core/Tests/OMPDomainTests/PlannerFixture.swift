import Foundation
import OMPDomain

/// Hand-built households and libraries for the planner tests (T10).
enum PlannerFixture {
    static let utc = TimeZone(identifier: "UTC")!
    static let now = Date(timeIntervalSince1970: 1_791_763_200)  // 2026-10-12T00:00:00Z
    static let monday = LocalDate(year: 2026, month: 10, day: 12)!
    static let day: TimeInterval = 86_400

    static let adult: MemberID = "m-adult"
    static let child: MemberID = "m-child"

    // MARK: Ingredients

    static func ingredient(
        _ id: IngredientID, tags: Set<FoodTag> = [], mayContain: Set<FoodTag> = [], status: TagStatus = .verified
    ) -> Ingredient {
        Ingredient(
            id: id, name: id.rawValue, tags: tags, mayContain: mayContain, tagStatus: status, aisle: .other,
            defaultUnit: .gram, defaultLocation: .shelf)
    }

    static let ingredients: [Ingredient] = [
        ingredient("rice"),
        ingredient("toor-dal"),
        ingredient("poha-flakes"),
        ingredient("semolina", tags: [.wheat, .gluten]),
        ingredient("peanuts", tags: [.peanut]),
        ingredient("ghee", tags: [.milk]),
        ingredient("curd", tags: [.milk]),
        ingredient("hing", mayContain: [.wheat, .gluten]),
        ingredient("atta", tags: [.wheat, .gluten]),
        ingredient("egg", tags: [.egg]),
        ingredient("rajma"),
        ingredient("vegetables"),
        ingredient("banana"),
        ingredient("chana"),
        ingredient("lemon"),
        ingredient("mystery-masala", status: .unverified),
    ]

    // MARK: Recipes

    static func recipe(
        _ id: RecipeID, _ types: Set<MealType>, _ lines: [IngredientID], optional: Set<IngredientID> = [],
        lunchbox: Bool = false, declared: Set<FoodTag> = []
    ) -> Recipe {
        Recipe(
            id: id, title: id.rawValue, region: "southIndian", mealTypes: types, lunchboxSuitable: lunchbox,
            servings: 4, prepMinutes: 10, cookMinutes: 20,
            ingredients: lines.map {
                RecipeIngredientLine(ingredientId: $0, quantity: 100, unit: .gram, isOptional: optional.contains($0))
            },
            steps: ["Cook."], declaredTags: declared, provenance: RecipeProvenance(source: "test"),
            review: RecipeReview(status: .signedOff))
    }

    /// Separate pools per slot (3 or more each) so the default plan never needs to relax variety.
    static let recipes: [Recipe] = [
        recipe("b-idli", [.breakfast], ["rice", "toor-dal"]),
        // Peanuts only on an optional line: still a peanut recipe.
        recipe("b-poha", [.breakfast], ["poha-flakes", "peanuts"], optional: ["peanuts"]),
        recipe("b-upma", [.breakfast], ["semolina", "vegetables"]),
        recipe("l-rajma", [.lunch], ["rajma", "rice"]),
        recipe("l-sambar-rice", [.lunch], ["toor-dal", "rice", "vegetables"]),
        recipe("l-curd-rice", [.lunch], ["curd", "rice"]),
        // Hing (may contain wheat/gluten) on an optional line.
        recipe("d-dal-tadka", [.dinner], ["toor-dal", "ghee", "hing"], optional: ["hing"]),
        recipe("d-chapati-sabzi", [.dinner], ["atta", "vegetables"]),
        recipe("d-veg-pulao", [.dinner], ["rice", "vegetables"]),
        recipe("d-egg-curry", [.dinner], ["egg", "vegetables"]),
        // An ingredient missing from the taxonomy: never plannable (fail closed).
        recipe("d-ghost", [.dinner], ["rice", "ghost"]),
        recipe("s-banana", [.snack], ["banana"]),
        recipe("s-chana", [.snack], ["chana"]),
        recipe("s-masala-chana", [.snack], ["chana", "mystery-masala"]),
        recipe("x-lemon-rice", [], ["rice", "lemon"], lunchbox: true),
        recipe("x-paratha", [], ["atta", "vegetables"], lunchbox: true),
        recipe("x-curd-rice", [], ["curd", "rice"], lunchbox: true),
    ]

    static let library = PlannerLibrary(recipes: recipes, ingredients: ingredients, contentVersion: "seed-test")

    static func makeLibrary(_ recipes: [Recipe]) -> PlannerLibrary {
        PlannerLibrary(recipes: recipes, ingredients: ingredients, contentVersion: "seed-test")
    }

    // MARK: Households

    static func rule(_ id: RuleID, _ scope: RuleScope, _ tags: Set<FoodTag>) -> Rule {
        Rule(id: id, scope: scope, restriction: RestrictionID(id.rawValue), excludedTags: tags, createdAt: now)
    }

    static func household(
        rules: [Rule] = [], snacks: Bool = false, lunchbox: Bool = false, childPortionOverride: Double? = nil
    ) -> Household {
        Household(
            id: "household-1",
            members: [
                Member(
                    id: adult, label: MemberLabel(role: .adult, number: 1), ageBand: .adult,
                    safetyStatus: rules.isEmpty ? .confirmedNone : .stated, safetyConfirmedAt: now),
                Member(
                    id: child, label: MemberLabel(role: .child, number: 1), ageBand: .child,
                    safetyStatus: rules.isEmpty ? .confirmedNone : .stated, safetyConfirmedAt: now,
                    needsSchoolLunch: lunchbox, schoolDays: lunchbox ? Weekday.schoolWeek : [],
                    portionOverride: childPortionOverride),
            ],
            rules: rules, settings: HouseholdSettings(snacksEnabled: snacks), createdAt: now, updatedAt: now)
    }

    static func clearance(_ household: Household, at instant: Date = now) throws -> SafetyClearance {
        try SafetyGate.evaluate(household, now: instant, timeZone: utc).get()
    }

    static func request(seed: PlannerSeed? = PlannerSeed(42), absences: Set<MealAbsence> = []) -> WeekPlanRequest {
        WeekPlanRequest(planId: "plan-1", seriesId: "series-1", weekStart: monday, absences: absences, seed: seed)
    }

    /// Clears `household` with the gate and generates a week from `monday`.
    static func generate(
        _ household: Household, library: PlannerLibrary = PlannerFixture.library, seed: PlannerSeed? = PlannerSeed(42),
        absences: Set<MealAbsence> = []
    ) throws -> MealPlan {
        try WeekPlanner.generateWeek(
            clearance: clearance(household), household: household, library: library,
            request: request(seed: seed, absences: absences), now: now, timeZone: utc)
    }

    static func meals(_ plan: MealPlan, _ slot: MealSlot) -> [PlannedMeal] {
        plan.meals.filter { $0.slot == slot }
    }
}
