import Foundation
import OMPDomain
import Testing

private typealias P = PlannerFixture
private typealias S = ScoringFixture

/// Helpers for swap, re-roll and regenerate (T11).
private enum Edit {
    /// A one-meal plan: `recipe` on Monday in `slot`, eaten by both members unless `servings` is given.
    static func singleMealPlan(
        _ recipe: RecipeID?, slot: MealSlot = .dinner, servings: [MealServing]? = nil, locked: Bool = false
    ) -> MealPlan {
        let meal = PlannedMeal(
            id: "meal-1", date: P.monday, slot: slot, recipeId: recipe, locked: locked,
            servings: servings
                ?? [MealServing(memberId: P.adult, portion: 1), MealServing(memberId: P.child, portion: 0.6)])
        return MealPlan(
            id: "plan-1", seriesId: "series-1", weekStart: P.monday, meals: [meal], contentVersion: "seed-test",
            createdAt: P.now)
    }

    static func alternatives(
        _ plan: MealPlan, meal: PlannedMealID = "meal-1", household: Household = P.household(),
        library: PlannerLibrary = P.library, reason: RerollReason? = nil, limit: Int = 3,
        signals: PlannerSignals = PlannerSignals()
    ) throws -> [RecipeID] {
        try WeekPlanner.alternatives(
            for: meal, in: plan, reason: reason, limit: limit, clearance: P.clearance(household), household: household,
            library: library, signals: signals, now: P.now, timeZone: P.utc
        ).map(\.recipeId)
    }

    static func reroll(
        _ plan: MealPlan, meal: PlannedMealID = "meal-1", household: Household = P.household(),
        library: PlannerLibrary = P.library, reason: RerollReason? = nil, excluding: Set<RecipeID> = [],
        signals: PlannerSignals = PlannerSignals(), seed: PlannerSeed? = nil
    ) throws -> PlannedMeal? {
        try WeekPlanner.reroll(
            meal, in: plan, reason: reason, excluding: excluding, clearance: P.clearance(household),
            household: household, library: library, signals: signals, seed: seed, now: P.now, timeZone: P.utc)
    }

    static func regenerate(
        _ plan: MealPlan, keepingLocked: Bool = true, household: Household = P.household(),
        library: PlannerLibrary = P.library, at now: Date = P.now
    ) throws -> [PlannedMeal] {
        try WeekPlanner.regenerate(
            plan, keepingLocked: keepingLocked, clearance: P.clearance(household, at: now), household: household,
            library: library, now: now, timeZone: P.utc)
    }

    static func error(_ body: () throws -> Void) -> PlannerError? {
        do {
            try body()
            return nil
        } catch let error as PlannerError {
            return error
        } catch {
            Issue.record("unexpected error: \(error)")
            return nil
        }
    }
}

@Suite("WeekPlanner.alternatives: swap (AC-8.1, UX U7)")
struct PlannerAlternativesTests {
    @Test("at most 3, never the current recipe, all from the hard filter, best first")
    func atMostThreeSafe() throws {
        let household = P.household(rules: [P.rule("milk", .member(P.child), [.milk])])
        let plan = Edit.singleMealPlan("d-veg-pulao")
        let ids = try Edit.alternatives(plan, household: household)
        // Safe dinners for a milk-free child: chapati sabzi, egg curry (dal tadka has ghee).
        #expect(ids == ["d-chapati-sabzi", "d-egg-curry"])
        let all = try Edit.alternatives(Edit.singleMealPlan("d-veg-pulao"), limit: 10)
        #expect(all == ["d-chapati-sabzi", "d-dal-tadka", "d-egg-curry"])
        #expect(try Edit.alternatives(plan, limit: 0) == [])
        #expect(try Edit.alternatives(plan, limit: -1) == [])

        // A bigger pool is cut to 3, ranked by score: pantry coverage puts egg curry first.
        var recipes = P.recipes
        recipes.append(P.recipe("d-extra", [.dinner], ["rice"]))
        let signals = PlannerSignals(pantry: [S.pantry("egg")])
        let ranked = try Edit.alternatives(plan, library: P.makeLibrary(recipes), signals: signals)
        #expect(ranked.count == 3)
        #expect(ranked.first == "d-egg-curry")
        #expect(!ranked.contains("d-veg-pulao"))
    }

    @Test("alternatives carry explanations")
    func explained() throws {
        let plan = Edit.singleMealPlan("d-veg-pulao")
        let alternatives = try WeekPlanner.alternatives(
            for: "meal-1", in: plan, clearance: P.clearance(P.household()), household: P.household(),
            library: P.library, now: P.now, timeZone: P.utc)
        #expect(alternatives.allSatisfy { !$0.reasons.isEmpty })
        let swapped = plan.meals[0].replacingRecipe(with: alternatives[0])
        #expect(swapped.recipeId == alternatives[0].recipeId)
        #expect(swapped.id == plan.meals[0].id && swapped.servings == plan.meals[0].servings)
    }

    @Test("variety-respecting options come first; repeats are offered last with the relaxation reason")
    func varietyFirst() throws {
        var plan = Edit.singleMealPlan("d-veg-pulao")
        plan.meals.append(
            PlannedMeal(
                id: "meal-2", date: P.monday.adding(days: 1), slot: .dinner, recipeId: "d-chapati-sabzi",
                servings: plan.meals[0].servings))
        let alternatives = try WeekPlanner.alternatives(
            for: "meal-1", in: plan, limit: 10, clearance: P.clearance(P.household()), household: P.household(),
            library: P.library, now: P.now, timeZone: P.utc)
        #expect(alternatives.map(\.recipeId) == ["d-dal-tadka", "d-egg-curry", "d-chapati-sabzi"])
        #expect(alternatives[2].reasons.first == .repeatedFewSafeOptions)
        #expect(!alternatives[0].reasons.contains(.repeatedFewSafeOptions))
    }

    @Test("a cleared member missing from the servings is treated as eating (fail closed)")
    func missingMemberIsEater() throws {
        let household = P.household(rules: [P.rule("egg", .member(P.child), [.egg])])
        let adultOnly = Edit.singleMealPlan("d-veg-pulao", servings: [MealServing(memberId: P.adult, portion: 1)])
        #expect(try !Edit.alternatives(adultOnly, household: household, limit: 10).contains("d-egg-curry"))
        // Explicitly not eating: the child's rule no longer constrains the meal (AC-6.3).
        let childOut = Edit.singleMealPlan(
            "d-veg-pulao",
            servings: [
                MealServing(memberId: P.adult, portion: 1),
                MealServing(memberId: P.child, portion: 0.6, notEating: true),
            ])
        #expect(try Edit.alternatives(childOut, household: household, limit: 10).contains("d-egg-curry"))
    }

    @Test("refuses a stale clearance, an unknown meal and a locked meal")
    func refusals() throws {
        let household = P.household()
        let clearance = try P.clearance(household)
        var edited = household
        edited.rules.append(P.rule("egg", .household, [.egg]))
        let plan = Edit.singleMealPlan("d-veg-pulao")
        let stale = Edit.error {
            _ = try WeekPlanner.alternatives(
                for: "meal-1", in: plan, clearance: clearance, household: edited, library: P.library, now: P.now,
                timeZone: P.utc)
        }
        #expect(stale == .clearanceNotValid)
        let notFound = Edit.error { _ = try Edit.alternatives(plan, meal: "nope") }
        #expect(notFound == .mealNotFound("nope"))
        let locked = Edit.singleMealPlan("d-veg-pulao", locked: true)
        let lockedError = Edit.error { _ = try Edit.alternatives(locked) }
        #expect(lockedError == .mealLocked("meal-1"))
    }
}

@Suite("WeekPlanner.reroll: Pick for me (AC-8.2)")
struct PlannerRerollTests {
    @Test("never the current recipe; nil only when no other safe recipe exists")
    func neverCurrent() throws {
        for seed in UInt64(0)..<20 {
            let meal = try #require(try Edit.reroll(Edit.singleMealPlan("d-veg-pulao"), seed: PlannerSeed(seed)))
            #expect(meal.recipeId != "d-veg-pulao")
            #expect(["d-chapati-sabzi", "d-dal-tadka", "d-egg-curry"].contains(meal.recipeId))
            #expect(meal.id == "meal-1" && meal.emptyReason == nil && !meal.reasons.isEmpty)
        }
        // Egg is unsafe; chapati is the only other safe dinner.
        let household = P.household(rules: [P.rule("r", .household, [.egg, .milk])])
        let rerolled = try Edit.reroll(Edit.singleMealPlan("d-veg-pulao"), household: household)
        #expect(rerolled?.recipeId == "d-chapati-sabzi")
        let only = P.makeLibrary([P.recipe("d-veg-pulao", [.dinner], ["rice", "vegetables"])])
        #expect(try Edit.reroll(Edit.singleMealPlan("d-veg-pulao"), library: only) == nil)
    }

    @Test("an empty meal can be re-rolled into a safe recipe")
    func emptyMeal() throws {
        let meal = try #require(try Edit.reroll(Edit.singleMealPlan(nil)))
        #expect(meal.recipeId != nil)
        #expect(meal.emptyReason == nil)
    }

    @Test("excluding skips recipes already rejected in this sheet")
    func excluding() throws {
        let plan = Edit.singleMealPlan("d-veg-pulao")
        let meal = try Edit.reroll(plan, excluding: ["d-chapati-sabzi", "d-dal-tadka"])
        #expect(meal?.recipeId == "d-egg-curry")
        #expect(try Edit.reroll(plan, excluding: ["d-chapati-sabzi", "d-dal-tadka", "d-egg-curry"]) == nil)
    }

    @Test("too long: only shorter recipes, even when a longer one scores higher")
    func tooLong() throws {
        func dinner(_ id: RecipeID, minutes: Int, _ lines: [IngredientID]) -> Recipe {
            var recipe = P.recipe(id, [.dinner], lines)
            recipe.prepMinutes = 0
            recipe.cookMinutes = minutes
            return recipe
        }
        let library = P.makeLibrary([
            dinner("d-current", minutes: 60, ["rice"]),
            dinner("d-longer", minutes: 90, ["rajma"]),
            dinner("d-shorter", minutes: 50, ["chana"]),
        ])
        let signals = PlannerSignals(pantry: [S.pantry("rajma")])
        let plan = Edit.singleMealPlan("d-current")
        #expect(try Edit.reroll(plan, library: library, signals: signals)?.recipeId == "d-longer")
        #expect(try Edit.reroll(plan, library: library, reason: .tooLong, signals: signals)?.recipeId == "d-shorter")
        #expect(try Edit.alternatives(plan, library: library, reason: .tooLong, signals: signals) == ["d-shorter"])
        // Nothing shorter: any other safe recipe rather than nothing.
        let longest = Edit.singleMealPlan("d-shorter")
        let quickLibrary = P.makeLibrary([
            dinner("d-shorter", minutes: 5, ["rice"]), dinner("d-other", minutes: 30, ["chana"]),
        ])
        let fallback = try Edit.reroll(longest, library: quickLibrary, reason: .tooLong)
        #expect(fallback?.recipeId == "d-other")
    }

    @Test("don't feel like it: prefers recipes sharing fewer ingredients with the current one")
    func dontFeelLikeIt() throws {
        // Current: rice + vegetables. Chapati and egg curry share vegetables; dal tadka shares nothing.
        for seed in UInt64(0)..<10 {
            let meal = try Edit.reroll(
                Edit.singleMealPlan("d-veg-pulao"), reason: .dontFeelLikeIt, seed: PlannerSeed(seed))
            #expect(meal?.recipeId == "d-dal-tadka")
        }
    }

    @Test("kids won't eat it: prefers lunchbox-suitable recipes with fewer shared ingredients")
    func kidsWontEatIt() throws {
        let library = P.makeLibrary([
            P.recipe("l-current", [.lunch], ["rice", "toor-dal"]),
            P.recipe("l-plain", [.lunch], ["rajma"]),
            P.recipe("l-kid", [.lunch], ["chana"], lunchbox: true),
            P.recipe("l-similar", [.lunch], ["rice", "toor-dal", "lemon"], lunchbox: true),
        ])
        for seed in UInt64(0)..<10 {
            let meal = try Edit.reroll(
                Edit.singleMealPlan("l-current", slot: .lunch), library: library, reason: .kidsWontEatIt,
                seed: PlannerSeed(seed))
            #expect(meal?.recipeId == "l-kid")
        }
    }

    @Test("deterministic: the same inputs give the same pick")
    func deterministic() throws {
        let plan = try P.generate(P.household(snacks: true))
        for meal in plan.meals {
            #expect(try Edit.reroll(plan, meal: meal.id) == Edit.reroll(plan, meal: meal.id))
        }
    }

    @Test("refuses a locked meal (AC-8.3) and an overdue clearance")
    func refusals() throws {
        let lockedError = Edit.error { _ = try Edit.reroll(Edit.singleMealPlan("d-veg-pulao", locked: true)) }
        #expect(lockedError == .mealLocked("meal-1"))
        let household = P.household()
        let clearance = try P.clearance(household)
        let overdue = Edit.error {
            _ = try WeekPlanner.reroll(
                "meal-1", in: Edit.singleMealPlan("d-veg-pulao"), reason: nil, clearance: clearance,
                household: household, library: P.library, now: P.now + 181 * P.day, timeZone: P.utc)
        }
        #expect(overdue == .clearanceNotValid)
    }
}

@Suite("WeekPlanner.regenerate (AC-8.3)")
struct PlannerRegenerateTests {
    @Test("locked meals are unchanged; ids and order are kept; others are replanned safely")
    func lockedUnchanged() throws {
        let household = P.household(rules: [P.rule("milk", .member(P.child), [.milk])], snacks: true, lunchbox: true)
        var plan = try P.generate(household)
        let lockedIndices = [0, 5, 11, 20]
        for index in lockedIndices {
            plan.meals[index].locked = true
        }
        let clearance = try P.clearance(household)
        for seed in UInt64(0)..<5 {
            let meals = try WeekPlanner.regenerate(
                plan, clearance: clearance, household: household, library: P.library, seed: PlannerSeed(seed),
                now: P.now, timeZone: P.utc)
            #expect(meals.map(\.id) == plan.meals.map(\.id))
            for index in lockedIndices {
                #expect(meals[index] == plan.meals[index])
            }
            for meal in meals where !meal.locked {
                let allowed = HardFilter.candidates(
                    for: meal.slot, eaterIDs: meal.eaterIDs, library: P.library, clearance: clearance
                ).map(\.id)
                let id = try #require(meal.recipeId)
                #expect(allowed.contains(id))
                #expect(!meal.reasons.isEmpty)
            }
        }
    }

    @Test("keepingLocked false replans locked meals too and unlocks them")
    func notKeepingLocked() throws {
        var plan = try P.generate(P.household())
        plan.meals[2].locked = true
        let meals = try Edit.regenerate(plan, keepingLocked: false)
        #expect(meals.allSatisfy { !$0.locked })
        #expect(meals.allSatisfy { !$0.reasons.contains(.lockedMealNoLongerSafe) })
    }

    @Test("a locked meal that is no longer safe is replanned (safety over lock)")
    func unsafeLockedReplanned() throws {
        var plan = try P.generate(P.household())
        let index = try #require(plan.meals.firstIndex { $0.slot == .dinner })
        plan.meals[index].recipeId = "d-egg-curry"
        plan.meals[index].locked = true
        let household = P.household(rules: [P.rule("egg", .household, [.egg])])
        let meals = try Edit.regenerate(plan, household: household)
        #expect(meals[index].recipeId != "d-egg-curry")
        #expect(!meals[index].locked)
        #expect(!meals.contains { $0.recipeId == "d-egg-curry" })
        // T11 review-1: the UI is told why a locked meal changed, first and only on that meal.
        #expect(meals[index].reasons.first == .lockedMealNoLongerSafe)
        #expect(meals[index].reasons.count <= 2)
        for (offset, meal) in meals.enumerated() where offset != index {
            #expect(!meal.reasons.contains(.lockedMealNoLongerSafe), "\(meal.id)")
        }
        // An unlocked meal that is replanned, and a still-safe locked meal, carry no such reason.
        #expect(try Edit.regenerate(plan).allSatisfy { !$0.reasons.contains(.lockedMealNoLongerSafe) })
    }

    @Test("cooked meals and days before today are kept")
    func pastAndCookedKept() throws {
        let household = P.household()
        var plan = try P.generate(household)
        let lastIndex = plan.meals.count - 1
        plan.meals[lastIndex].cooked = CookRef(cookLogId: "cook-1", cookedAt: P.now)
        let wednesday = P.now + 2 * P.day
        let meals = try Edit.regenerate(plan, household: household, at: wednesday)
        for (old, new) in zip(plan.meals, meals) where old.date < P.monday.adding(days: 2) {
            #expect(old == new)
        }
        #expect(meals[lastIndex] == plan.meals[lastIndex])
    }

    @Test("variety holds around kept meals")
    func varietyAroundLocked() throws {
        var plan = try P.generate(P.household())
        for index in plan.meals.indices where plan.meals[index].slot == .dinner && index % 2 == 0 {
            plan.meals[index].locked = true
        }
        let meals = try Edit.regenerate(plan)
        let dinners = meals.filter { $0.slot == .dinner }
        for (i, a) in dinners.enumerated() {
            for b in dinners[(i + 1)...] where a.recipeId == b.recipeId {
                #expect(abs(b.date.daysSince(a.date)) >= WeekPlanner.varietyWindowDays, "\(a.id) \(b.id)")
            }
        }
    }

    @Test("deterministic, and refuses a stale clearance")
    func deterministicAndRefusesStale() throws {
        let household = P.household(snacks: true)
        var plan = try P.generate(household)
        plan.meals[1].locked = true
        #expect(try Edit.regenerate(plan) == Edit.regenerate(plan))

        let clearance = try P.clearance(household)
        var edited = household
        edited.rules.append(P.rule("egg", .household, [.egg]))
        let stale = Edit.error {
            _ = try WeekPlanner.regenerate(
                plan, clearance: clearance, household: edited, library: P.library, now: P.now, timeZone: P.utc)
        }
        #expect(stale == .clearanceNotValid)
    }
}
