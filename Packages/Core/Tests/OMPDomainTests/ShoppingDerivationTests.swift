import Foundation
import OMPDomain
import Testing

@Suite("Shopping derivation (T14: AC-5.3, AC-6.4, AC-9.2, AC-10.1, AC-10.2, AC-10.4)")
struct ShoppingDerivationTests {
    typealias F = ShoppingFixture

    // MARK: which plan and meals count

    @Test("AC-5.3: a draft plan yields no derived lines")
    func draftPlanYieldsNothing() {
        let draft = PlanFixture.draft(meals: [PlanFixture.meal("meal-1", recipe: "dal-tadka")])
        #expect(F.derive(draft).isEmpty)
        #expect(IngredientRequirements.forShopping(
            plan: draft, recipes: F.recipes, ingredients: F.ingredients, today: F.today).isEmpty)
    }

    @Test("AC-5.3, AC-5.5: an approved plan edited after approval (hash mismatch) yields nothing")
    func editedApprovedPlanYieldsNothing() throws {
        var plan = try F.dalPlan()
        #expect(!F.derive(plan).isEmpty)
        plan.meals[0].recipeId = "rajma-chawal"
        #expect(!plan.isEffectivelyApproved)
        #expect(F.derive(plan).isEmpty)
    }

    @Test("AC-10.2: superseded and discarded plans yield nothing", arguments: [PlanStatus.superseded, .discarded])
    func closedPlansYieldNothing(status: PlanStatus) throws {
        var plan = try F.dalPlan()
        plan.status = status
        #expect(F.derive(plan).isEmpty)
    }

    @Test("R1, AC-9.6: meals blocked by safety, cooked meals and past meals are excluded")
    func blockedCookedAndPastMealsExcluded() throws {
        var plan = try F.approved([
            PlanFixture.meal("meal-past", day: 0, recipe: "dal-tadka"),
            PlanFixture.meal("meal-blocked", day: 1, recipe: "rajma-chawal"),
            PlanFixture.meal("meal-cooked", day: 2, recipe: "rajma-chawal"),
            PlanFixture.meal("meal-open", day: 3, recipe: "palak-paneer"),
            PlanFixture.meal("meal-empty", day: 4, recipe: nil),
        ])
        let blocked = try #require(plan.meals.firstIndex { $0.id == "meal-blocked" })
        let cooked = try #require(plan.meals.firstIndex { $0.id == "meal-cooked" })
        plan.meals[blocked].blockedBySafety = true
        plan.meals[cooked].cooked = CookRef(cookLogId: "cook-1", cookedAt: Sample.later)
        #expect(plan.isEffectivelyApproved)

        let tomorrow = F.now.addingTimeInterval(F.day)
        let lines = F.derive(plan, now: tomorrow)
        #expect(Set(lines.map(\.ingredientId)) == ["paneer", "milk", "coriander"])
    }

    @Test("a meal whose recipe is unknown contributes nothing")
    func unknownRecipeSkipped() throws {
        let plan = try F.approved([PlanFixture.meal("meal-1", recipe: "no-such-recipe")])
        #expect(F.derive(plan).isEmpty)
    }

    // MARK: requirements arithmetic (AC-6.4, AC-10.1)

    @Test("AC-6.4: quantity x sum of portions / recipe servings, unit-normalised; to-taste lines omitted")
    func workedExampleDal() throws {
        let lines = F.derive(try F.dalPlan())
        #expect(lines.count == 3)
        #expect(F.holds(F.find(lines, "plan:toor-dal:mass:toBuy"), 80, .gram))
        // 2 tbsp x 0.4 = 0.8 tbsp = 12 ml (ghee's default unit is volume, shown in ml).
        #expect(F.holds(F.find(lines, "plan:ghee:volume:toBuy"), 12, .millilitre))
        #expect(F.holds(F.find(lines, "plan:onion:count:toBuy"), 0.8, .piece))
        #expect(!lines.contains { $0.ingredientId == "salt" })
        // Sorted by aisle display order: vegetables, pulses, oils.
        #expect(lines.map(\.ingredientId) == ["onion", "toor-dal", "ghee"])
        let dal = try #require(F.find(lines, "plan:toor-dal:mass:toBuy"))
        #expect(dal.name == "Toor dal" && dal.aisle == .pulsesAndLentils && dal.group == .toBuy)
    }

    @Test("AC-6.4: a member who is not eating adds no portion")
    func notEatingMemberExcluded() throws {
        let servings = [
            MealServing(memberId: PlanFixture.adult, portion: 1.0),
            MealServing(memberId: PlanFixture.child, portion: 0.6, notEating: true),
        ]
        let plan = try F.approved([PlanFixture.meal("meal-1", recipe: "dal-tadka", servings: servings)])
        #expect(F.holds(F.find(F.derive(plan), "plan:toor-dal:mass:toBuy"), 50, .gram))
    }

    @Test("AC-10.1: amounts sum across meals and convert through the piece weight")
    func sumsAcrossMeals() throws {
        let plan = try F.approved([
            PlanFixture.meal("meal-1", day: 0, recipe: "dal-tadka"),
            PlanFixture.meal("meal-2", day: 1, recipe: "dal-tadka"),
            PlanFixture.meal("meal-3", day: 2, recipe: "rajma-chawal"),
        ])
        let lines = F.derive(plan)
        #expect(F.holds(F.find(lines, "plan:toor-dal:mass:toBuy"), 160, .gram))
        // 0.8 + 0.8 piece + 80 g (= 80/150 piece at 150 g per piece), shown in pieces.
        #expect(F.holds(F.find(lines, "plan:onion:count:toBuy"), 1.6 + 80.0 / 150.0, .piece))
        #expect(lines.filter { $0.ingredientId == "onion" }.count == 1)
    }

    @Test("AC-10.1: non-convertible amounts of one ingredient stay separate lines")
    func nonConvertibleSeparateLines() throws {
        let plan = try F.approved([
            PlanFixture.meal("meal-1", day: 0, recipe: "rajma-chawal"),
            PlanFixture.meal("meal-2", day: 1, recipe: "palak-paneer"),
        ])
        let coriander = F.derive(plan).filter { $0.ingredientId == "coriander" }
        #expect(coriander.count == 2)
        #expect(F.holds(F.find(coriander, "plan:coriander:mass:toBuy"), 8, .gram))
        #expect(F.holds(F.find(coriander, "plan:coriander:count:toBuy"), 0.4, .piece))
    }

    @Test("AC-6.4: 1000 g or more is shown in kg")
    func largeMassShownInKilograms() throws {
        let meals = (0..<6).map { PlanFixture.meal(PlannedMealID("meal-\($0)"), day: $0, recipe: "rajma-chawal") }
        let lines = F.derive(try F.approved(meals))
        #expect(F.holds(F.find(lines, "plan:rice:mass:toBuy"), 1.2, .kilogram))
    }

    @Test("the display unit does not depend on the order meals are summed in")
    func displayUnitIsOrderIndependent() throws {
        let gramsFirst = try F.approved([
            PlanFixture.meal("meal-1", day: 0, recipe: "rajma-chawal"),
            PlanFixture.meal("meal-2", day: 1, recipe: "dal-tadka"),
        ])
        let piecesFirst = try F.approved([
            PlanFixture.meal("meal-1", day: 0, recipe: "dal-tadka"),
            PlanFixture.meal("meal-2", day: 1, recipe: "rajma-chawal"),
        ])
        let lhs = try #require(F.find(F.derive(gramsFirst), "plan:onion:count:toBuy"))
        let rhs = try #require(F.find(F.derive(piecesFirst), "plan:onion:count:toBuy"))
        #expect(lhs.quantity.unit == rhs.quantity.unit && F.approx(lhs.quantity.amount, rhs.quantity.amount))
    }

    @Test("an ingredient missing from the dictionary is still listed, by id, in the Other aisle")
    func unknownIngredientListed() throws {
        let recipe = F.recipe("mystery", servings: 1, [F.line("ghost", 100, .gram)])
        let plan = try F.approved([PlanFixture.meal("meal-1", recipe: "mystery")])
        let lines = ShoppingDerivation.derive(
            plan: plan, recipes: [recipe.id: recipe], ingredients: F.ingredients, pantry: [], now: F.now,
            timeZone: F.utc)
        let line = try #require(lines.first)
        #expect(line.name == "ghost" && line.aisle == .other)
        #expect(F.holds(line, 160, .gram))
    }

    // MARK: need = requirements - usable pantry (AC-10.1, AC-9.2)

    @Test("AC-10.1: confident pantry is subtracted; a fully covered need has no line")
    func confidentPantrySubtracted() throws {
        let plan = try F.dalPlan()
        let partial = F.derive(plan, pantry: [F.pantry("p1", "toor-dal", 50, .gram)])
        #expect(F.holds(F.find(partial, "plan:toor-dal:mass:toBuy"), 30, .gram))

        let covered = F.derive(plan, pantry: [F.pantry("p1", "toor-dal", 0.1, .kilogram)])
        #expect(!covered.contains { $0.ingredientId == "toor-dal" })
        #expect(covered.count == 2)
    }

    @Test("AC-10.1: pantry in a different but convertible unit is subtracted")
    func pantryConvertsAcrossDimensions() throws {
        // 12 ml of ghee needed; 9.1 g of ghee = 10 ml at 0.91 g/ml.
        let lines = F.derive(try F.dalPlan(), pantry: [F.pantry("p1", "ghee", 9.1, .gram)])
        #expect(F.holds(F.find(lines, "plan:ghee:volume:toBuy"), 2, .millilitre))
    }

    @Test("AC-10.1: pantry that does not convert covers only the matching line")
    func nonConvertiblePantryCoversOnlyItsLine() throws {
        let plan = try F.approved([
            PlanFixture.meal("meal-1", day: 0, recipe: "rajma-chawal"),
            PlanFixture.meal("meal-2", day: 1, recipe: "palak-paneer"),
        ])
        let lines = F.derive(plan, pantry: [F.pantry("p1", "coriander", 1, .piece)])
        #expect(F.find(lines, "plan:coriander:count:toBuy") == nil)
        #expect(F.holds(F.find(lines, "plan:coriander:mass:toBuy"), 8, .gram))
    }

    @Test("AC-9.2: an unresolved free-text pantry item never covers a requirement")
    func freeTextNeverCounts() throws {
        let item = F.pantry("p1", nil, 5, .kilogram, freeText: "toor dal")
        #expect(!item.isUsableForRequirements(today: F.today))
        let lines = F.derive(try F.dalPlan(), pantry: [item])
        #expect(F.holds(F.find(lines, "plan:toor-dal:mass:toBuy"), 80, .gram))
    }

    @Test("expired pantry does not count; an item expiring today still does")
    func expiredPantryIgnored() throws {
        let plan = try F.dalPlan()
        let expired = F.derive(plan, pantry: [F.pantry("p1", "toor-dal", 1, .kilogram, expiresOn: F.today.adding(days: -1))])
        #expect(F.holds(F.find(expired, "plan:toor-dal:mass:toBuy"), 80, .gram))
        let lastDay = F.derive(plan, pantry: [F.pantry("p1", "toor-dal", 1, .kilogram, expiresOn: F.today)])
        #expect(F.find(lastDay, "plan:toor-dal:mass:toBuy") == nil)
    }

    @Test("zero, negative and to-taste pantry amounts cover nothing")
    func emptyPantryAmountsIgnored() throws {
        let lines = F.derive(
            try F.dalPlan(),
            pantry: [
                F.pantry("p1", "toor-dal", 0, .gram), F.pantry("p2", "toor-dal", -100, .gram),
                F.pantry("p3", "toor-dal", 5, .toTaste),
            ])
        #expect(F.holds(F.find(lines, "plan:toor-dal:mass:toBuy"), 80, .gram))
    }

    // MARK: Check you have (AC-10.4)

    static func paneerPlan() throws -> MealPlan {
        try F.approved([PlanFixture.meal("meal-1", recipe: "palak-paneer")])
    }

    @Test("AC-10.4: low-confidence cover goes to Check you have, the rest to To buy")
    func lowConfidencePartialCover() throws {
        // Milk needed: 40 ml. 30 ml in the fridge, last confirmed 8 days ago (low confidence).
        let lines = F.derive(
            try Self.paneerPlan(), pantry: [F.pantry("p1", "milk", 30, .millilitre, location: .fridge, confirmedDaysAgo: 8)])
        #expect(F.holds(F.find(lines, "plan:milk:volume:checkYouHave"), 30, .millilitre))
        #expect(F.holds(F.find(lines, "plan:milk:volume:toBuy"), 10, .millilitre))
        #expect(F.find(lines, "plan:milk:volume:checkYouHave")?.group == .checkYouHave)
    }

    @Test("AC-10.4: a need fully covered by low-confidence pantry is only a Check you have line")
    func lowConfidenceFullCover() throws {
        let lines = F.derive(
            try Self.paneerPlan(), pantry: [F.pantry("p1", "milk", 1, .litre, location: .fridge, confirmedDaysAgo: 30)])
        #expect(F.holds(F.find(lines, "plan:milk:volume:checkYouHave"), 40, .millilitre))
        #expect(F.find(lines, "plan:milk:volume:toBuy") == nil)
    }

    @Test("AC-10.4: confident pantry is used first; only what remains is checked")
    func confidentBeforeLowConfidence() throws {
        let lines = F.derive(
            try Self.paneerPlan(),
            pantry: [
                F.pantry("p1", "milk", 100, .millilitre, location: .fridge, confirmedDaysAgo: 9),
                F.pantry("p2", "milk", 25, .millilitre, location: .fridge, confirmedDaysAgo: 1),
            ])
        #expect(F.holds(F.find(lines, "plan:milk:volume:checkYouHave"), 15, .millilitre))
        #expect(F.find(lines, "plan:milk:volume:toBuy") == nil)
    }

    @Test("AC-9.7, AC-10.4: a fridge item confirmed 7 days ago is still subtracted silently")
    func fridgeDaySevenStillConfident() throws {
        let lines = F.derive(
            try Self.paneerPlan(), pantry: [F.pantry("p1", "milk", 100, .millilitre, location: .fridge, confirmedDaysAgo: 7)])
        #expect(!lines.contains { $0.ingredientId == "milk" })
    }

    // MARK: optional lines (T14 review)

    @Test("optional recipe lines stay off the shopping list but are still scaled for Mark cooked")
    func optionalLinesOnlyLeaveTheShoppingList() throws {
        let recipe = F.recipe(
            "garnished", servings: 4,
            [F.line("rice", 200, .gram),
             RecipeIngredientLine(ingredientId: "coriander", quantity: 8, unit: .gram, isOptional: true)])
        let plan = try F.approved([PlanFixture.meal("meal-1", day: 0, recipe: "garnished")])
        let lines = ShoppingDerivation.derive(
            plan: plan, recipes: ["garnished": recipe], ingredients: F.ingredients, pantry: [], now: F.now,
            timeZone: F.utc)
        #expect(lines.map(\.ingredientId) == ["rice"])

        let amounts = try MarkCooked.proposedAmounts(
            mealId: "meal-1", in: plan, recipe: recipe, ingredients: F.ingredients)
        #expect(Set(amounts.map(\.ingredientId)) == ["rice", "coriander"])
    }
}
