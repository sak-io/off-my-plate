import Foundation
import OMPDomain
import Testing

@Suite("Pantry confidence decay (T14: AC-9.7)")
struct PantryConfidenceTests {
    typealias F = ShoppingFixture

    @Test("AC-9.7: windows are 7 days for the fridge and 60 for the shelf and the freezer")
    func windows() {
        #expect(StorageLocation.fridge.confidenceWindowDays == 7)
        #expect(StorageLocation.shelf.confidenceWindowDays == 60)
        #expect(StorageLocation.freezer.confidenceWindowDays == 60)
    }

    static let boundaryCases: [(StorageLocation, Double, PantryConfidence)] = [
        (.fridge, 0, .confident),
        (.fridge, 7, .confident),
        (.fridge, 8, .low),
        (.shelf, 60, .confident),
        (.shelf, 61, .low),
        (.freezer, 60, .confident),
        (.freezer, 61, .low),
    ]

    @Test("AC-9.7: decay boundaries (last confident day, first low day)", arguments: PantryConfidenceTests.boundaryCases)
    func boundaries(location: StorageLocation, daysAgo: Double, expected: PantryConfidence) {
        let item = F.pantry("p1", "milk", 1, .litre, location: location, confirmedDaysAgo: daysAgo)
        #expect(item.confidence(now: F.now, timeZone: F.utc) == expected)
    }

    @Test("AC-9.7: re-confirming resets the confidence")
    func reconfirmResets() {
        var item = F.pantry("p1", "milk", 1, .litre, location: .fridge, confirmedDaysAgo: 30)
        #expect(item.confidence(now: F.now, timeZone: F.utc) == .low)
        item.lastConfirmedAt = F.now
        #expect(item.confidence(now: F.now, timeZone: F.utc) == .confident)
    }

    @Test("age counts calendar days in the given time zone, not 24-hour periods")
    func calendarDaysInTimeZone() {
        // Confirmed 2026-10-04 23:30 UTC. In UTC+2 that is already 2026-10-05 01:30.
        let confirmed = Date(timeIntervalSince1970: 1_791_763_200 - 7 * 86_400 - 1_800)
        var item = F.pantry("p1", "milk", 1, .litre, location: .fridge)
        item.lastConfirmedAt = confirmed
        let plusTwo = TimeZone(secondsFromGMT: 7_200)!
        // now = 2026-10-12 00:00 UTC (02:00 in UTC+2).
        #expect(item.daysSinceConfirmed(now: F.now, timeZone: F.utc) == 8)
        #expect(item.confidence(now: F.now, timeZone: F.utc) == .low)
        #expect(item.daysSinceConfirmed(now: F.now, timeZone: plusTwo) == 7)
        #expect(item.confidence(now: F.now, timeZone: plusTwo) == .confident)
    }

    @Test("a confirmation in the future (clock change) counts as today")
    func futureConfirmationIsAgeZero() {
        let item = F.pantry("p1", "milk", 1, .litre, location: .fridge, confirmedDaysAgo: -3)
        #expect(item.daysSinceConfirmed(now: F.now, timeZone: F.utc) == 0)
        #expect(item.confidence(now: F.now, timeZone: F.utc) == .confident)
    }

    @Test("AC-9.2: usability needs a resolved, unexpired, positive amount")
    func usability() {
        #expect(F.pantry("p1", "rice", 1, .kilogram).isUsableForRequirements(today: F.today))
        #expect(!F.pantry("p2", nil, 1, .kilogram).isUsableForRequirements(today: F.today))
        #expect(!F.pantry("p3", "rice", 0, .kilogram).isUsableForRequirements(today: F.today))
        #expect(!F.pantry("p4", "rice", 1, .pinch).isUsableForRequirements(today: F.today))
        #expect(!F.pantry("p5", "rice", 1, .kilogram, expiresOn: F.today.adding(days: -1)).isUsableForRequirements(today: F.today))
        #expect(F.pantry("p6", "rice", 1, .kilogram, expiresOn: F.today).isUsableForRequirements(today: F.today))
    }
}

@Suite("Mark cooked deduction (T14: AC-5.3, AC-9.6)")
struct MarkCookedTests {
    typealias F = ShoppingFixture

    static func amounts(_ plan: MealPlan, meal: PlannedMealID = "meal-1", recipe: Recipe = ShoppingFixture.dalTadka)
        throws -> [CookAmount]
    {
        try MarkCooked.proposedAmounts(mealId: meal, in: plan, recipe: recipe, ingredients: F.ingredients)
    }

    @Test("AC-5.3, AC-9.6: Mark cooked is unavailable on a draft plan")
    func draftRefused() {
        let draft = PlanFixture.draft(meals: [PlanFixture.meal("meal-1", recipe: "dal-tadka")])
        #expect(F.cookError { try Self.amounts(draft) } == MarkCookedError.planNotApproved)
    }

    @Test("AC-5.5: Mark cooked is unavailable on an approved plan edited after approval")
    func editedPlanRefused() throws {
        var plan = try F.dalPlan()
        plan.meals[0].servings = [MealServing(memberId: PlanFixture.adult, portion: 2)]
        #expect(F.cookError { try Self.amounts(plan) } == MarkCookedError.planNotApproved)
    }

    @Test("R1: Mark cooked is unavailable for a meal blocked by safety")
    func blockedRefused() throws {
        var plan = try F.dalPlan()
        plan.meals[0].blockedBySafety = true
        #expect(F.cookError { try Self.amounts(plan) } == MarkCookedError.blockedBySafety("meal-1"))
    }

    @Test("a meal cannot be cooked twice; unknown, empty and mismatched meals are refused")
    func otherRefusals() throws {
        var plan = try F.approved([
            PlanFixture.meal("meal-1", day: 0, recipe: "dal-tadka"),
            PlanFixture.meal("meal-2", day: 1, recipe: nil),
        ])
        #expect(F.cookError { try Self.amounts(plan, meal: "nope") } == MarkCookedError.mealNotFound("nope"))
        #expect(F.cookError { try Self.amounts(plan, meal: "meal-2") } == MarkCookedError.emptyMeal("meal-2"))
        #expect(
            F.cookError { try Self.amounts(plan, recipe: F.rajmaChawal) }
                == MarkCookedError.recipeMismatch(expected: "dal-tadka", actual: "rajma-chawal"))
        let index = try #require(plan.meals.firstIndex { $0.id == "meal-1" })
        plan.meals[index].cooked = CookRef(cookLogId: "cook-1", cookedAt: F.now)
        #expect(F.cookError { try Self.amounts(plan) } == MarkCookedError.alreadyCooked("meal-1"))
    }

    @Test("AC-9.6: proposed amounts are recipe quantities x servings; to-taste lines are left out")
    func proposedAmounts() throws {
        let amounts = try Self.amounts(try F.dalPlan())
        #expect(amounts.map(\.ingredientId) == ["ghee", "onion", "toor-dal"])
        #expect(amounts[0].quantity.unit == .tablespoon && F.approx(amounts[0].quantity.amount, 0.8))
        #expect(amounts[1].quantity.unit == .piece && F.approx(amounts[1].quantity.amount, 0.8))
        #expect(amounts[2].quantity.unit == .gram && F.approx(amounts[2].quantity.amount, 80))
    }

    @Test("AC-9.6: deduction takes from the earliest expiry first; items without expiry last")
    func earliestExpiryFirst() {
        let pantry = [
            F.pantry("no-expiry", "toor-dal", 500, .gram),
            F.pantry("later", "toor-dal", 500, .gram, expiresOn: F.today.adding(days: 30)),
            F.pantry("sooner", "toor-dal", 50, .gram, expiresOn: F.today.adding(days: 3)),
        ]
        let result = MarkCooked.deduct(
            [CookAmount(ingredientId: "toor-dal", quantity: Quantity(80, .gram))], from: pantry,
            ingredients: F.ingredients)
        #expect(result.pantry.map(\.id) == ["no-expiry", "later", "sooner"])
        #expect(result.pantry.map(\.quantity) == [500, 470, 0])
        #expect(
            result.deductions == [
                PantryDeduction(pantryItemId: "sooner", quantity: 50, unit: .gram),
                PantryDeduction(pantryItemId: "later", quantity: 30, unit: .gram),
            ])
    }

    @Test("AC-9.6: quantities never go below zero when the pantry has too little")
    func neverNegative() {
        let pantry = [F.pantry("p1", "toor-dal", 30, .gram), F.pantry("p2", "toor-dal", 0.02, .kilogram)]
        let result = MarkCooked.deduct(
            [CookAmount(ingredientId: "toor-dal", quantity: Quantity(1, .kilogram))], from: pantry,
            ingredients: F.ingredients)
        #expect(result.pantry.allSatisfy { $0.quantity == 0 })
        #expect(
            result.deductions == [
                PantryDeduction(pantryItemId: "p1", quantity: 30, unit: .gram),
                PantryDeduction(pantryItemId: "p2", quantity: 0.02, unit: .kilogram),
            ])
    }

    @Test("AC-9.6: deduction converts units (grams from a kilogram bag, ml of ghee from grams)")
    func deductionConverts() {
        let pantry = [F.pantry("dal", "toor-dal", 1, .kilogram), F.pantry("ghee", "ghee", 91, .gram)]
        let result = MarkCooked.deduct(
            [
                CookAmount(ingredientId: "toor-dal", quantity: Quantity(80, .gram)),
                CookAmount(ingredientId: "ghee", quantity: Quantity(2, .tablespoon)),  // 30 ml = 27.3 g
            ],
            from: pantry, ingredients: F.ingredients)
        #expect(F.approx(result.pantry[0].quantity, 0.92) && result.pantry[0].unit == .kilogram)
        #expect(F.approx(result.pantry[1].quantity, 63.7) && result.pantry[1].unit == .gram)
    }

    @Test("AC-9.2: free-text items, other ingredients and non-convertible units are never touched")
    func untouchedItems() {
        let pantry = [
            F.pantry("text", nil, 1, .kilogram, freeText: "toor dal"),
            F.pantry("rice", "rice", 1, .kilogram),
            F.pantry("bunch", "coriander", 2, .piece),
        ]
        let result = MarkCooked.deduct(
            [
                CookAmount(ingredientId: "toor-dal", quantity: Quantity(80, .gram)),
                CookAmount(ingredientId: "coriander", quantity: Quantity(10, .gram)),
            ],
            from: pantry, ingredients: F.ingredients)
        #expect(result.pantry == pantry)
        #expect(result.deductions.isEmpty)
    }

    @Test("AC-9.6: edited amounts on the confirm sheet are what gets deducted; zero deducts nothing")
    func editedAmounts() throws {
        var amounts = try Self.amounts(try F.dalPlan())
        let pantry = [F.pantry("dal", "toor-dal", 500, .gram), F.pantry("onion", "onion", 3, .piece)]
        amounts[1].quantity = Quantity(0, .piece)  // the user cooked without onion
        amounts[2].quantity = Quantity(120, .gram)  // and used more dal
        let result = MarkCooked.deduct(amounts, from: pantry, ingredients: F.ingredients)
        #expect(result.pantry.map(\.quantity) == [380, 3])
        #expect(result.deductions == [PantryDeduction(pantryItemId: "dal", quantity: 120, unit: .gram)])
    }
}
