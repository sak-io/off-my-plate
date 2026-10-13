import Foundation
import OMPDomain
import OMPRecipes
import OMPSafetyCheck
import Testing

/// Cross-check (T10, AC-4.1, ADR 0007): every draft the planner produces passes the independent
/// `PlanValidator`. The planner and validator share no code; this test is where they meet.
/// T11 adds scoring signals and the editing entry points (swap, re-roll, regenerate).
/// T12's safety suite extends this to restriction pairs and generated households.
private enum Agreement {
    static let utc = TimeZone(identifier: "UTC")!
    static let now = Date(timeIntervalSince1970: 1_791_763_200)  // 2026-10-12T00:00:00Z
    static let monday = LocalDate(year: 2026, month: 10, day: 12)!
    static let adult: MemberID = "m-adult"
    static let child: MemberID = "m-child"

    static func household(rules: [Rule], snacks: Bool = true) -> Household {
        let status: SafetyStatus = rules.isEmpty ? .confirmedNone : .stated
        return Household(
            id: "household-1",
            members: [
                Member(
                    id: adult, label: MemberLabel(role: .adult, number: 1), ageBand: .adult, safetyStatus: status,
                    safetyConfirmedAt: now),
                Member(
                    id: child, label: MemberLabel(role: .child, number: 1), ageBand: .child, safetyStatus: status,
                    safetyConfirmedAt: now, needsSchoolLunch: true, schoolDays: Weekday.schoolWeek),
            ],
            rules: rules, settings: HouseholdSettings(snacksEnabled: snacks), createdAt: now, updatedAt: now)
    }

    /// Plans with the planner, then validates with the validator; returns the report.
    static func planAndValidate(
        _ household: Household, recipes: [Recipe], ingredients: [Ingredient], seed: UInt64,
        absences: Set<MealAbsence> = []
    ) throws -> (MealPlan, ValidationReport) {
        let clearance = try SafetyGate.evaluate(household, now: now, timeZone: utc).get()
        let plan = try WeekPlanner.generateWeek(
            clearance: clearance, household: household,
            library: PlannerLibrary(recipes: recipes, ingredients: ingredients, contentVersion: "test"),
            request: WeekPlanRequest(
                planId: "plan-1", seriesId: "series-1", weekStart: monday, absences: absences,
                seed: PlannerSeed(seed)),
            now: now, timeZone: utc)
        let report = PlanValidator.validate(
            plan, household: household, library: SafetyCheckLibrary(recipes: recipes, ingredients: ingredients))
        return (plan, report)
    }

    static func ingredient(
        _ id: IngredientID, tags: Set<FoodTag> = [], mayContain: Set<FoodTag> = [], status: TagStatus = .verified
    ) -> Ingredient {
        Ingredient(
            id: id, name: id.rawValue, tags: tags, mayContain: mayContain, tagStatus: status, aisle: .other,
            defaultUnit: .gram, defaultLocation: .shelf)
    }

    static func recipe(
        _ id: RecipeID, _ types: Set<MealType>, _ lines: [IngredientID], optional: Set<IngredientID> = [],
        lunchbox: Bool = false
    ) -> Recipe {
        Recipe(
            id: id, title: id.rawValue, region: "southIndian", mealTypes: types, lunchboxSuitable: lunchbox,
            servings: 4, prepMinutes: 10, cookMinutes: 20,
            ingredients: lines.map {
                RecipeIngredientLine(ingredientId: $0, quantity: 100, unit: .gram, isOptional: optional.contains($0))
            },
            steps: ["Cook."], declaredTags: [], provenance: RecipeProvenance(source: "test"),
            review: RecipeReview(status: .signedOff))
    }

    /// Every soft signal pointing at every recipe: favourites, cuisine affinity, and every
    /// ingredient in the pantry and about to expire. Scores must never beat the hard filter.
    static func maximalSignals(recipes: [Recipe], ingredients: [Ingredient]) -> PlannerSignals {
        var facts: [Fact] = recipes.map {
            Fact(
                id: FactID("fav-" + $0.id.rawValue), statement: .favouriteRecipe($0.id), origin: .stated,
                confidence: 1, status: .active, createdAt: now, updatedAt: now)
        }
        for region in Set(recipes.map(\.region)).sorted() {
            facts.append(
                Fact(
                    id: FactID("cuisine-" + region.rawValue), statement: .cuisineAffinity(region), origin: .confirmed,
                    confidence: 1, status: .active, createdAt: now, updatedAt: now))
        }
        let pantry = ingredients.map {
            PantryItem(
                id: PantryItemID("p-" + $0.id.rawValue), item: .ingredient($0.id), quantity: 1, unit: .kilogram,
                location: .shelf, expiresOn: monday.adding(days: 1), lastConfirmedAt: now, source: .manual)
        }
        return PlannerSignals(pantry: pantry, facts: facts)
    }

    /// Exercises every T11 entry point on `household` and returns every resulting plan:
    /// the scored week, every meal swapped to each alternative, every meal re-rolled with each
    /// reason, and a regenerate with every third meal locked.
    static func editedPlans(
        _ household: Household, recipes: [Recipe], ingredients: [Ingredient], seed: UInt64
    ) throws -> [MealPlan] {
        let clearance = try SafetyGate.evaluate(household, now: now, timeZone: utc).get()
        let library = PlannerLibrary(recipes: recipes, ingredients: ingredients, contentVersion: "test")
        let signals = maximalSignals(recipes: recipes, ingredients: ingredients)
        var plan = try WeekPlanner.generateWeek(
            clearance: clearance, household: household, library: library,
            request: WeekPlanRequest(
                planId: "plan-1", seriesId: "series-1", weekStart: monday, seed: PlannerSeed(seed)),
            signals: signals, now: now, timeZone: utc)

        let reasons: [RerollReason?] = [nil, .dontFeelLikeIt, .tooLong, .kidsWontEatIt]
        var swapped: [PlannedMeal] = []
        var rerolled: [PlannedMeal] = []
        for meal in plan.meals {
            let alternatives = try WeekPlanner.alternatives(
                for: meal.id, in: plan, clearance: clearance, household: household, library: library,
                signals: signals, now: now, timeZone: utc)
            swapped += alternatives.map { meal.replacingRecipe(with: $0) }
            for reason in reasons {
                if let replacement = try WeekPlanner.reroll(
                    meal.id, in: plan, reason: reason, clearance: clearance, household: household, library: library,
                    signals: signals, now: now, timeZone: utc)
                {
                    rerolled.append(replacement)
                }
            }
        }
        var swappedPlan = plan
        swappedPlan.meals = swapped
        var rerolledPlan = plan
        rerolledPlan.meals = rerolled

        for index in plan.meals.indices where index % 3 == 0 {
            plan.meals[index].locked = true
        }
        var regenerated = plan
        regenerated.meals = try WeekPlanner.regenerate(
            plan, clearance: clearance, household: household, library: library, signals: signals, now: now,
            timeZone: utc)
        return [plan, swappedPlan, rerolledPlan, regenerated]
    }

    /// A tricky library: optional may-contain lines, unverified ingredients, undeclared tags,
    /// a recipe with an ingredient missing from the taxonomy.
    static let ingredients: [Ingredient] = [
        ingredient("rice"), ingredient("dal"), ingredient("peanuts", tags: [.peanut]),
        ingredient("ghee", tags: [.milk]), ingredient("hing", mayContain: [.wheat, .gluten]),
        ingredient("atta", tags: [.wheat, .gluten]), ingredient("egg", tags: [.egg]),
        ingredient("chicken", tags: [.poultry]), ingredient("onion", tags: [.onion, .rootVegetable]),
        ingredient("masala", status: .unverified),
    ]
    static let recipes: [Recipe] = [
        recipe("poha", [.breakfast, .snack], ["rice", "peanuts"], optional: ["peanuts"], lunchbox: true),
        recipe("idli", [.breakfast], ["rice", "dal"], lunchbox: true),
        recipe("egg-bhurji", [.breakfast, .dinner], ["egg", "onion"]),
        recipe("dal-tadka", [.lunch, .dinner], ["dal", "ghee", "hing"], optional: ["hing"]),
        recipe("chicken-curry", [.lunch, .dinner], ["chicken", "onion", "masala"]),
        recipe("roti", [.lunch, .dinner], ["atta"], lunchbox: true),
        recipe("plain-rice", [.lunch, .dinner, .snack], ["rice"], lunchbox: true),
        recipe("mystery", [.lunch, .dinner, .breakfast], ["rice", "not-in-taxonomy"], lunchbox: true),
    ]
}

@Suite("Planner output passes PlanValidator (T10, AC-4.1, ADR 0007)")
struct PlannerValidatorAgreementTests {
    @Test("bundled seed: every restriction, member or household scope, several seeds")
    func bundledSeedEveryRestriction() throws {
        let seedLibrary = try SeedLoader.loadBundled()
        var households = [Agreement.household(rules: [])]
        for restriction in seedLibrary.catalog.restrictions {
            for scope in [RuleScope.member(Agreement.child), .member(Agreement.adult), .household] {
                let rule = Rule(id: "rule-1", scope: scope, restriction: restriction, createdAt: Agreement.now)
                households.append(Agreement.household(rules: [rule]))
            }
        }
        for household in households {
            for seed in UInt64(0)..<3 {
                let (plan, report) = try Agreement.planAndValidate(
                    household, recipes: seedLibrary.recipes, ingredients: seedLibrary.ingredients, seed: seed)
                #expect(report.passedForEveryone, "\(household.rules.map(\.restriction)): \(report.violations)")
                #expect(plan.status == .draft)
            }
        }
    }

    @Test("T11: scored plans, swaps, re-rolls and regenerate pass on the bundled seed for every restriction")
    func bundledSeedEditing() throws {
        let seedLibrary = try SeedLoader.loadBundled()
        var households = [Agreement.household(rules: [])]
        for restriction in seedLibrary.catalog.restrictions {
            for scope in [RuleScope.member(Agreement.child), .household] {
                let rule = Rule(id: "rule-1", scope: scope, restriction: restriction, createdAt: Agreement.now)
                households.append(Agreement.household(rules: [rule]))
            }
        }
        var checkedMeals = 0
        for household in households {
            let plans = try Agreement.editedPlans(
                household, recipes: seedLibrary.recipes, ingredients: seedLibrary.ingredients, seed: 1)
            for plan in plans {
                let report = PlanValidator.validate(
                    plan, household: household,
                    library: SafetyCheckLibrary(recipes: seedLibrary.recipes, ingredients: seedLibrary.ingredients))
                #expect(report.passedForEveryone, "\(household.rules.map(\.restriction)): \(report.violations)")
                checkedMeals += plan.meals.filter { $0.recipeId != nil }.count
            }
        }
        #expect(checkedMeals > 0)
    }

    @Test("T11: edits on the tricky library pass for every tag combination")
    func trickyLibraryEditing() throws {
        let tagSets: [Set<FoodTag>] = [[], [.peanut], [.milk], [.wheat, .gluten], [.egg], [.poultry, .onion]]
        for tags in tagSets {
            for scope in [RuleScope.member(Agreement.child), .household] {
                let rules: [Rule] =
                    tags.isEmpty
                    ? [] : [Rule(id: "r", scope: scope, restriction: "r", excludedTags: tags, createdAt: Agreement.now)]
                let household = Agreement.household(rules: rules)
                for seed in UInt64(0)..<3 {
                    let plans = try Agreement.editedPlans(
                        household, recipes: Agreement.recipes, ingredients: Agreement.ingredients, seed: seed)
                    for plan in plans {
                        let report = PlanValidator.validate(
                            plan, household: household,
                            library: SafetyCheckLibrary(recipes: Agreement.recipes, ingredients: Agreement.ingredients))
                        #expect(report.passedForEveryone, "\(tags) \(scope) seed \(seed): \(report.violations)")
                        #expect(!plan.meals.contains { $0.recipeId == "mystery" })
                    }
                }
            }
        }
    }

    @Test("tricky library: tag combinations, absences and lunchboxes all pass")
    func trickyLibrary() throws {
        let tagSets: [Set<FoodTag>] = [
            [], [.peanut], [.milk], [.wheat, .gluten], [.egg], [.poultry], [.onion, .rootVegetable, .garlic],
            [.peanut, .milk, .wheat, .gluten, .egg],
        ]
        let absences: Set<MealAbsence> = [
            MealAbsence(memberId: Agreement.child, date: Agreement.monday, slot: .dinner),
            MealAbsence(memberId: Agreement.adult, date: Agreement.monday.adding(days: 1), slot: .lunch),
        ]
        var filled = 0
        for tags in tagSets {
            for scope in [RuleScope.member(Agreement.child), .household] {
                let rules: [Rule] =
                    tags.isEmpty
                    ? [] : [Rule(id: "r", scope: scope, restriction: "r", excludedTags: tags, createdAt: Agreement.now)]
                for seed in UInt64(0)..<5 {
                    let (plan, report) = try Agreement.planAndValidate(
                        Agreement.household(rules: rules), recipes: Agreement.recipes,
                        ingredients: Agreement.ingredients, seed: seed, absences: absences)
                    #expect(report.passedForEveryone, "\(tags) \(scope) seed \(seed): \(report.violations)")
                    #expect(!plan.meals.contains { $0.recipeId == "mystery" })
                    filled += plan.meals.filter { $0.recipeId != nil }.count
                }
            }
        }
        // The check is not vacuous: the planner did fill meals.
        #expect(filled > 0)
    }
}
