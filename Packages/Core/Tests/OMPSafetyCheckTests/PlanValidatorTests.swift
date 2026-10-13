import Foundation
import OMPDomain
import OMPSafetyCheck
import Testing

/// Hand-built households, ingredients, recipes and plans for the validator tests (T09).
private enum VFixture {
    static let now = Date(timeIntervalSince1970: 1_791_763_200)  // 2026-10-12T00:00:00Z
    static let monday = LocalDate(year: 2026, month: 10, day: 12)!

    static let adult: MemberID = "m-adult"
    static let child: MemberID = "m-child"

    static func ingredient(
        _ id: IngredientID, tags: Set<FoodTag> = [], mayContain: Set<FoodTag> = [], status: TagStatus = .verified
    ) -> Ingredient {
        Ingredient(
            id: id, name: id.rawValue, tags: tags, mayContain: mayContain, tagStatus: status,
            aisle: .other, defaultUnit: .gram, defaultLocation: .shelf)
    }

    static let rice = ingredient("rice")
    static let toorDal = ingredient("toor-dal")
    static let ghee = ingredient("ghee", tags: [.milk])
    static let hing = ingredient("hing", mayContain: [.wheat, .gluten])
    static let peanuts = ingredient("peanuts", tags: [.peanut])
    static let onion = ingredient("onion", tags: [.onion, .rootVegetable])
    static let mysteryMasala = ingredient("mystery-masala", status: .unverified)

    static func recipe(
        _ id: RecipeID, _ lines: [IngredientID], optional: Set<IngredientID> = [], declared: Set<FoodTag> = []
    ) -> Recipe {
        Recipe(
            id: id, title: id.rawValue, region: "north", mealTypes: [.lunch, .dinner], servings: 4,
            prepMinutes: 10, cookMinutes: 20,
            ingredients: lines.map {
                RecipeIngredientLine(ingredientId: $0, quantity: 100, unit: .gram, isOptional: optional.contains($0))
            },
            steps: ["Cook."], declaredTags: declared, provenance: RecipeProvenance(source: "test"),
            review: RecipeReview(status: .signedOff))
    }

    /// Plain rice and dal: no tags at all.
    static let plainKhichdi = recipe("plain-khichdi", ["rice", "toor-dal"])
    /// Hing (may contain wheat/gluten) as an optional garnish; ghee (milk).
    static let dalTadka = recipe("dal-tadka", ["toor-dal", "ghee", "hing"], optional: ["hing"])
    /// Peanuts, but the author forgot to declare the tag: the validator must not trust it.
    static let peanutSalad = recipe("peanut-salad", ["onion", "peanuts"], declared: [.onion, .rootVegetable])
    static let masalaRice = recipe("masala-rice", ["rice", "mystery-masala"])
    static let brokenRecipe = recipe("broken", ["rice", "not-in-taxonomy"])

    static let library = SafetyCheckLibrary(
        recipes: [plainKhichdi, dalTadka, peanutSalad, masalaRice, brokenRecipe],
        ingredients: [rice, toorDal, ghee, hing, peanuts, onion, mysteryMasala])

    static func rule(_ id: RuleID, _ scope: RuleScope, _ tags: Set<FoodTag>) -> Rule {
        Rule(id: id, scope: scope, restriction: RestrictionID(id.rawValue), excludedTags: tags, createdAt: now)
    }

    static func household(rules: [Rule]) -> Household {
        Household(
            id: "household-1",
            members: [
                Member(id: adult, label: MemberLabel(role: .adult, number: 1), ageBand: .adult, safetyStatus: .stated),
                Member(id: child, label: MemberLabel(role: .child, number: 1), ageBand: .child, safetyStatus: .stated),
            ],
            rules: rules, createdAt: now, updatedAt: now)
    }

    static func meal(_ id: PlannedMealID, recipe: RecipeID?, servings: [MealServing]) -> PlannedMeal {
        PlannedMeal(id: id, date: monday, slot: .dinner, recipeId: recipe, servings: servings)
    }

    static func meal(
        _ id: PlannedMealID, recipe: RecipeID?, day: Int = 0, adultEating: Bool = true, childEating: Bool = true
    ) -> PlannedMeal {
        PlannedMeal(
            id: id, date: monday.adding(days: day), slot: .dinner, recipeId: recipe,
            emptyReason: recipe == nil ? .noSafeRecipe : nil,
            servings: [
                MealServing(memberId: adult, portion: 1.0, notEating: !adultEating),
                MealServing(memberId: child, portion: 0.6, notEating: !childEating),
            ])
    }

    static func plan(_ meals: [PlannedMeal]) -> MealPlan {
        MealPlan(id: "plan-1", seriesId: "series-1", weekStart: monday, meals: meals, contentVersion: "seed-1", createdAt: now)
    }

    static func validate(_ meals: [PlannedMeal], rules: [Rule], library: SafetyCheckLibrary = VFixture.library)
        -> ValidationReport
    {
        PlanValidator.validate(plan(meals), household: household(rules: rules), library: library)
    }
}

@Suite("Plan validator (ADR 0007)")
struct PlanValidatorTests {
    @Test("a clean plan passes for everyone and carries the plan id and content hash")
    func cleanPlanPasses() {
        let plan = VFixture.plan([
            VFixture.meal("meal-1", recipe: "plain-khichdi"),
            VFixture.meal("meal-2", recipe: "dal-tadka", day: 1),
            VFixture.meal("meal-3", recipe: nil, day: 2),
        ])
        let household = VFixture.household(rules: [VFixture.rule("peanuts", .member(VFixture.child), [.peanut])])
        let report = PlanValidator.validate(plan, household: household, library: VFixture.library)
        #expect(report.passedForEveryone)
        #expect(report.violations == [])
        #expect(report.planId == plan.id)
        #expect(report.contentHash == plan.contentHash)
    }

    @Test("a household with no rules passes even with tagged and unverified ingredients")
    func noRulesNoTagViolations() {
        let report = VFixture.validate(
            [VFixture.meal("meal-1", recipe: "peanut-salad"), VFixture.meal("meal-2", recipe: "masala-rice", day: 1)],
            rules: [])
        #expect(report.passedForEveryone)
    }

    @Test("AC-4.2: an excluded tag is a violation pinpointing meal, member and ingredient")
    func excludedTagPinpointsMealAndMember() {
        let report = VFixture.validate(
            [VFixture.meal("meal-1", recipe: "plain-khichdi"), VFixture.meal("meal-2", recipe: "peanut-salad", day: 1)],
            rules: [VFixture.rule("peanuts", .member(VFixture.child), [.peanut])])
        #expect(
            report.violations == [
                Violation(mealId: "meal-2", memberId: VFixture.child, kind: .excludedTag(.peanut, ingredient: "peanuts"))
            ])
        #expect(report.violatingMealIDs == ["meal-2"])
        #expect(!report.passedForEveryone)
    }

    @Test("tags are recomputed from ingredient lines, not taken from declaredTags")
    func ignoresDeclaredTags() {
        // peanut-salad declares only onion/rootVegetable; its peanuts line must still be caught.
        let report = VFixture.validate(
            [VFixture.meal("meal-1", recipe: "peanut-salad")],
            rules: [VFixture.rule("peanuts", .member(VFixture.adult), [.peanut])])
        #expect(report.violations.map(\.kind) == [.excludedTag(.peanut, ingredient: "peanuts")])
    }

    @Test("a declared tag with no matching ingredient is not a violation")
    func declaredTagAloneIsNotAViolation() {
        let declaredOnly = VFixture.recipe("declared-only", ["rice"], declared: [.peanut])
        let library = SafetyCheckLibrary(recipes: [declaredOnly], ingredients: [VFixture.rice])
        let report = VFixture.validate(
            [VFixture.meal("meal-1", recipe: "declared-only")],
            rules: [VFixture.rule("peanuts", .household, [.peanut])], library: library)
        #expect(report.passedForEveryone)
    }

    @Test("mayContain counts as contains, including on an optional line")
    func mayContainCountsAsContains() {
        let report = VFixture.validate(
            [VFixture.meal("meal-1", recipe: "dal-tadka")],
            rules: [VFixture.rule("gluten-free", .member(VFixture.adult), [.gluten])])
        #expect(
            report.violations == [
                Violation(mealId: "meal-1", memberId: VFixture.adult, kind: .excludedTag(.gluten, ingredient: "hing"))
            ])
    }

    @Test("every excluded tag of an ingredient is reported, in FoodTag order")
    func multipleTagsReported() {
        let report = VFixture.validate(
            [VFixture.meal("meal-1", recipe: "dal-tadka")],
            rules: [VFixture.rule("wheat-gluten", .member(VFixture.adult), [.gluten, .wheat, .milk])])
        #expect(
            report.violations.map(\.kind) == [
                .excludedTag(.milk, ingredient: "ghee"),
                .excludedTag(.wheat, ingredient: "hing"),
                .excludedTag(.gluten, ingredient: "hing"),
            ])
    }

    @Test("AC-4.3: an unverified ingredient violates for an eater with any hard rule")
    func unverifiedIngredientWithHardRule() {
        // The child's rule (sesame) is unrelated to the recipe, yet the unverified line fails it.
        let report = VFixture.validate(
            [VFixture.meal("meal-1", recipe: "masala-rice")],
            rules: [VFixture.rule("sesame", .member(VFixture.child), [.sesame])])
        #expect(
            report.violations == [
                Violation(mealId: "meal-1", memberId: VFixture.child, kind: .unverifiedIngredient("mystery-masala"))
            ])
    }

    @Test("AC-4.3: an unverified ingredient violates even for a hard rule with no excluded tags")
    func unverifiedIngredientWithEmptyRule() {
        let report = VFixture.validate(
            [VFixture.meal("meal-1", recipe: "masala-rice")],
            rules: [VFixture.rule("empty", .member(VFixture.adult), [])])
        #expect(report.violations.map(\.kind) == [.unverifiedIngredient("mystery-masala")])
        #expect(report.violations.map(\.memberId) == [VFixture.adult])
    }

    @Test("an unknown recipe fails closed for every eater, even without rules")
    func unknownRecipeFailsClosed() {
        let report = VFixture.validate([VFixture.meal("meal-1", recipe: "not-in-library")], rules: [])
        #expect(
            report.violations == [
                Violation(mealId: "meal-1", memberId: VFixture.adult, kind: .unknownRecipe("not-in-library")),
                Violation(mealId: "meal-1", memberId: VFixture.child, kind: .unknownRecipe("not-in-library")),
            ])
    }

    @Test("an ingredient missing from the taxonomy fails closed for every eater, even without rules")
    func unknownIngredientFailsClosed() {
        let report = VFixture.validate([VFixture.meal("meal-1", recipe: "broken")], rules: [])
        #expect(
            report.violations == [
                Violation(mealId: "meal-1", memberId: VFixture.adult, kind: .unknownIngredient("not-in-taxonomy")),
                Violation(mealId: "meal-1", memberId: VFixture.child, kind: .unknownIngredient("not-in-taxonomy")),
            ])
    }

    @Test("AC-6.3: a member who is not eating is ignored")
    func notEatingMemberIgnored() {
        let rules = [VFixture.rule("peanuts", .member(VFixture.child), [.peanut])]
        let skipped = VFixture.validate([VFixture.meal("meal-1", recipe: "peanut-salad", childEating: false)], rules: rules)
        #expect(skipped.passedForEveryone)

        let eating = VFixture.validate([VFixture.meal("meal-1", recipe: "peanut-salad")], rules: rules)
        #expect(eating.violations.map(\.memberId) == [VFixture.child])
    }

    @Test("a meal nobody eats is not checked, even with an unknown recipe")
    func mealWithNoEaters() {
        let report = VFixture.validate(
            [VFixture.meal("meal-1", recipe: "not-in-library", adultEating: false, childEating: false)],
            rules: [VFixture.rule("peanuts", .household, [.peanut])])
        #expect(report.passedForEveryone)
    }

    @Test("a household-scope rule applies to every eater")
    func householdScopeCoversEveryEater() {
        let report = VFixture.validate(
            [VFixture.meal("meal-1", recipe: "peanut-salad")],
            rules: [VFixture.rule("jain", .household, [.onion, .rootVegetable])])
        #expect(
            report.violations == [
                Violation(mealId: "meal-1", memberId: VFixture.adult, kind: .excludedTag(.rootVegetable, ingredient: "onion")),
                Violation(mealId: "meal-1", memberId: VFixture.adult, kind: .excludedTag(.onion, ingredient: "onion")),
                Violation(mealId: "meal-1", memberId: VFixture.child, kind: .excludedTag(.rootVegetable, ingredient: "onion")),
                Violation(mealId: "meal-1", memberId: VFixture.child, kind: .excludedTag(.onion, ingredient: "onion")),
            ])
    }

    @Test("a member-scope rule applies only to that member")
    func memberScopeCoversOnlyThatMember() {
        let report = VFixture.validate(
            [VFixture.meal("meal-1", recipe: "dal-tadka")],
            rules: [VFixture.rule("dairy", .member(VFixture.adult), [.milk])])
        #expect(report.violations.map(\.memberId) == [VFixture.adult])
    }

    @Test("member and household rules combine for one eater")
    func memberAndHouseholdRulesCombine() {
        let report = VFixture.validate(
            [VFixture.meal("meal-1", recipe: "dal-tadka")],
            rules: [
                VFixture.rule("dairy", .member(VFixture.child), [.milk]),
                VFixture.rule("gluten", .household, [.gluten]),
            ])
        #expect(
            report.violations == [
                Violation(mealId: "meal-1", memberId: VFixture.adult, kind: .excludedTag(.gluten, ingredient: "hing")),
                Violation(mealId: "meal-1", memberId: VFixture.child, kind: .excludedTag(.milk, ingredient: "ghee")),
                Violation(mealId: "meal-1", memberId: VFixture.child, kind: .excludedTag(.gluten, ingredient: "hing")),
            ])
    }

    @Test("violations across meals keep plan order and repeated lines are reported once")
    func deterministicOrderAcrossMeals() {
        let doubled = VFixture.recipe("double-peanut", ["peanuts", "rice", "peanuts"])
        let library = SafetyCheckLibrary(
            recipes: [VFixture.peanutSalad, doubled], ingredients: [VFixture.rice, VFixture.peanuts, VFixture.onion])
        let report = VFixture.validate(
            [
                VFixture.meal("meal-b", recipe: "double-peanut", adultEating: false),
                VFixture.meal("meal-a", recipe: "peanut-salad", day: 1, adultEating: false),
            ],
            rules: [VFixture.rule("peanuts", .member(VFixture.child), [.peanut])], library: library)
        #expect(
            report.violations == [
                Violation(mealId: "meal-b", memberId: VFixture.child, kind: .excludedTag(.peanut, ingredient: "peanuts")),
                Violation(mealId: "meal-a", memberId: VFixture.child, kind: .excludedTag(.peanut, ingredient: "peanuts")),
            ])
        #expect(report.violatingMealIDs == ["meal-b", "meal-a"])
    }

    @Test("duplicate ingredient ids merge conservatively: union of tags, unverified wins")
    func duplicateIngredientsMergeConservatively() {
        let cleanCopy = VFixture.ingredient("ghee")
        let taggedCopy = VFixture.ingredient("ghee", tags: [.milk], status: .unverified)
        let recipe = VFixture.recipe("ghee-rice", ["rice", "ghee"])
        let library = SafetyCheckLibrary(recipes: [recipe], ingredients: [VFixture.rice, cleanCopy, taggedCopy])
        let report = VFixture.validate(
            [VFixture.meal("meal-1", recipe: "ghee-rice", childEating: false)],
            rules: [VFixture.rule("dairy", .member(VFixture.adult), [.milk])], library: library)
        #expect(
            report.violations.map(\.kind) == [.unverifiedIngredient("ghee"), .excludedTag(.milk, ingredient: "ghee")])
    }

    @Test("duplicate recipe ids merge conservatively: every copy's lines are checked")
    func duplicateRecipesMergeConservatively() {
        let clean = VFixture.recipe("salad", ["rice"])
        let withPeanuts = VFixture.recipe("salad", ["peanuts"])
        let library = SafetyCheckLibrary(recipes: [clean, withPeanuts], ingredients: [VFixture.rice, VFixture.peanuts])
        let report = VFixture.validate(
            [VFixture.meal("meal-1", recipe: "salad", childEating: false)],
            rules: [VFixture.rule("peanuts", .household, [.peanut])], library: library)
        #expect(report.violations.map(\.kind) == [.excludedTag(.peanut, ingredient: "peanuts")])
    }

    // MARK: Eaters: household members missing from servings are still checked (fail closed)

    @Test("an active member omitted from servings is still an eater")
    func omittedMemberIsChecked() {
        let meal = VFixture.meal("meal-1", recipe: "peanut-salad", servings: [MealServing(memberId: VFixture.adult, portion: 1.0)])
        let report = VFixture.validate([meal], rules: [VFixture.rule("peanuts", .member(VFixture.child), [.peanut])])
        #expect(
            report.violations == [
                Violation(mealId: "meal-1", memberId: VFixture.child, kind: .excludedTag(.peanut, ingredient: "peanuts"))
            ])
    }

    @Test("a meal with empty servings checks every active member, in household order")
    func emptyServingsChecksEveryone() {
        let meal = VFixture.meal("meal-1", recipe: "peanut-salad", servings: [])
        let report = VFixture.validate([meal], rules: [VFixture.rule("peanuts", .household, [.peanut])])
        #expect(report.violations.map(\.memberId) == [VFixture.adult, VFixture.child])
    }

    @Test("a soft-deleted member missing from servings is ignored")
    func softDeletedMissingMemberIgnored() {
        let gone: MemberID = "m-gone"
        var household = VFixture.household(rules: [VFixture.rule("peanuts", .member(gone), [.peanut])])
        household.members.append(
            Member(
                id: gone, label: MemberLabel(role: .adult, number: 2), safetyStatus: .stated,
                deletedAt: VFixture.now))
        let plan = VFixture.plan([VFixture.meal("meal-1", recipe: "peanut-salad")])
        let report = PlanValidator.validate(plan, household: household, library: VFixture.library)
        #expect(report.passedForEveryone)
    }

    @Test("a missing member constrained only by a household rule violates")
    func missingMemberHouseholdRuleOnly() {
        let meal = VFixture.meal("meal-1", recipe: "dal-tadka", servings: [MealServing(memberId: VFixture.adult, portion: 1.0, notEating: true)])
        let report = VFixture.validate([meal], rules: [VFixture.rule("dairy", .household, [.milk])])
        #expect(
            report.violations == [
                Violation(mealId: "meal-1", memberId: VFixture.child, kind: .excludedTag(.milk, ingredient: "ghee"))
            ])
    }

    @Test("an eating serving beats a duplicate notEating serving for the same member")
    func eatingServingBeatsNotEating() {
        let meal = VFixture.meal(
            "meal-1", recipe: "peanut-salad",
            servings: [
                MealServing(memberId: VFixture.adult, portion: 1.0, notEating: true),
                MealServing(memberId: VFixture.child, portion: 0.6, notEating: true),
                MealServing(memberId: VFixture.child, portion: 0.6),
            ])
        let report = VFixture.validate([meal], rules: [VFixture.rule("peanuts", .household, [.peanut])])
        #expect(report.violations.map(\.memberId) == [VFixture.child])
    }

    @Test("eaters are ordered by servings first, then remaining household members")
    func eaterOrderServingsThenHousehold() {
        let guest: MemberID = "m-guest"
        let meal = VFixture.meal(
            "meal-1", recipe: "peanut-salad",
            servings: [MealServing(memberId: VFixture.child, portion: 0.6), MealServing(memberId: guest, portion: 1.0)])
        let report = VFixture.validate([meal], rules: [VFixture.rule("peanuts", .household, [.peanut])])
        #expect(report.violations.map(\.memberId) == [VFixture.child, guest, VFixture.adult])
    }
}
