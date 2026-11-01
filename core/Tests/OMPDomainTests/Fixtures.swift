import Foundation
import OMPDomain

/// Hand-built sample values covering every field (including optionals set and unset) for
/// the Codable round-trip tests. Instants are whole seconds so they survive JSON exactly.
enum Sample {
    static let now = Date(timeIntervalSince1970: 1_791_763_200)  // 2026-10-12T00:00:00Z
    static let later = Date(timeIntervalSince1970: 1_791_849_600)  // 2026-10-13T00:00:00Z
    static let monday = LocalDate(year: 2026, month: 10, day: 12)!

    static let adultID: MemberID = "member-adult-1"
    static let childID: MemberID = "member-child-1"

    static let peanuts = Restriction(id: "peanuts", labelKey: "restriction.peanuts", excludedTags: [.peanut])
    static let jain = Restriction(
        id: "jain", labelKey: "restriction.jain", excludedTags: [.rootVegetable, .onion, .garlic, .mushroom])

    static let adult = Member(
        id: adultID, label: MemberLabel(role: .adult, number: 1), name: "Asha", ageBand: .adult,
        safetyStatus: .confirmedNone, safetyConfirmedAt: now, portionOverride: 1.2)
    static let child = Member(
        id: childID, label: MemberLabel(role: .child, number: 1), ageBand: .child, safetyStatus: .stated,
        safetyConfirmedAt: now, needsSchoolLunch: true, schoolDays: Weekday.schoolWeek)
    static let deletedChild = Member(
        id: "member-child-2", label: MemberLabel(role: .child, number: 2), deletedAt: later)

    static let memberRule = Rule(id: "rule-1", scope: .member(childID), restriction: peanuts, createdAt: now)
    static let householdRule = Rule(id: "rule-2", scope: .household, restriction: jain, createdAt: now)

    static let household = Household(
        id: "household-1", members: [adult, child, deletedChild], rules: [memberRule, householdRule],
        settings: HouseholdSettings(snacksEnabled: true, weekStartsOn: .sunday), createdAt: now, updatedAt: later)

    static let ghee = Ingredient(
        id: "ghee", name: "Ghee", synonyms: ["clarified butter"], tags: [.milk], tagStatus: .verified,
        aisle: .oilsAndGhee, defaultUnit: .tablespoon, gramsPerMl: 0.91, defaultLocation: .shelf)
    static let hing = Ingredient(
        id: "hing", name: "Asafoetida", synonyms: ["hing"], mayContain: [.wheat, .gluten], tagStatus: .unverified,
        aisle: .spicesAndMasalas, defaultUnit: .pinch, gramsPerPiece: nil, defaultLocation: .shelf,
        fridgeShelfLifeDays: 365)

    static let recipe = Recipe(
        id: "dal-tadka", title: "Dal tadka", region: "northIndian", mealTypes: [.lunch, .dinner],
        lunchboxSuitable: true, servings: 4, prepMinutes: 10, cookMinutes: 25,
        ingredients: [
            RecipeIngredientLine(ingredientId: "ghee", quantity: 2, unit: .tablespoon),
            RecipeIngredientLine(ingredientId: "hing", quantity: 0, unit: .pinch, isOptional: true),
        ],
        steps: ["Cook the dal.", "Temper with ghee and hing."], declaredTags: [.milk, .wheat, .gluten],
        provenance: RecipeProvenance(source: "OffMyPlate team (original)", notes: "Test fixture"),
        review: RecipeReview(status: .signedOff, reviewer: "Owner", reviewedOn: monday))

    static let filledMeal = PlannedMeal(
        id: "meal-1", date: monday, slot: .dinner, recipeId: "dal-tadka", locked: true,
        servings: [
            MealServing(defaultFor: adult),
            MealServing(memberId: childID, portion: 0.6, notEating: true),
        ],
        reasons: [.usesYourIngredient("ghee"), .quickWeekday(.dinner), .repeatedFewSafeOptions],
        cooked: CookRef(cookLogId: "cook-1", cookedAt: later), blockedBySafety: true)
    static let emptyMeal = PlannedMeal(
        id: "meal-2", date: monday.adding(days: 1), slot: .lunchbox, recipeId: nil, emptyReason: .noSafeRecipe,
        servings: [MealServing(defaultFor: child)])

    static let approvedPlan = MealPlan(
        id: "plan-2", seriesId: "series-1", revision: 2, basedOn: "plan-1", weekStart: monday, status: .approved,
        meals: [filledMeal, emptyMeal],
        approval: PlanApproval(approvedAt: later, contentHash: String(repeating: "ab", count: 32)),
        contentVersion: "seed-1", createdAt: now)
    static let draftPlan = MealPlan(
        id: "plan-3", seriesId: "series-1", weekStart: monday, meals: [], contentVersion: "seed-1", createdAt: now)

    static let pantryResolved = PantryItem(
        id: "pantry-1", item: .ingredient("ghee"), quantity: 500, unit: .gram, location: .shelf, purchasedAt: now,
        expiresOn: monday.adding(days: 90), lastConfirmedAt: now, source: .bought)
    static let pantryFreeText = PantryItem(
        id: "pantry-2", item: .freeText("mystery pickle"), quantity: 1, unit: .piece, location: .fridge,
        lastConfirmedAt: later, source: .voice)

    static let shoppingDerived = ShoppingItem(
        id: "shop-1", key: "ghee|mass", ingredientId: "ghee", name: "Ghee", quantity: 250, unit: .gram,
        aisle: .oilsAndGhee, checkedOff: true, origin: .plan, group: .checkYouHave)
    static let shoppingManual = ShoppingItem(
        id: "shop-2", key: "manual:bin bags", name: "Bin bags", aisle: .other, origin: .manual)

    static let cookLog = CookLog(
        id: "cook-1", planId: "plan-2", mealId: "meal-1", recipeId: "dal-tadka", cookedAt: later,
        deductions: [PantryDeduction(pantryItemId: "pantry-1", quantity: 30, unit: .gram)])

    static let facts: [Fact] = [
        Fact(
            id: "fact-1", statement: .cuisineAffinity("southIndian"), origin: .stated, confidence: 1,
            status: .active, createdAt: now, updatedAt: now),
        Fact(
            id: "fact-2", subject: .member(childID), statement: .dislikesIngredient("okra"), origin: .inferred,
            confidence: 0.4, status: .proposed, createdAt: now, updatedAt: later),
        Fact(
            id: "fact-3", statement: .prefersQuickWeekday, origin: .appDefault, confidence: 0.5,
            status: .dismissed, suppressed: true, createdAt: now, updatedAt: later),
        Fact(
            id: "fact-4", statement: .staple("rice"), origin: .confirmed, confidence: 1, status: .forgotten,
            forgottenAt: later, createdAt: now, updatedAt: later),
        Fact(
            id: "fact-5", statement: .dislikesRecipe("upma"), origin: .inferred, confidence: 0.25,
            status: .observing, createdAt: now, updatedAt: now),
        Fact(
            id: "fact-6", statement: .favouriteRecipe("poha"), origin: .confirmed, confidence: 1, status: .active,
            createdAt: now, updatedAt: now),
    ]

    static let learningEvents: [LearningEvent] = [
        LearningEvent(id: "event-1", kind: .swapped(from: "upma", to: "poha", slot: .breakfast), at: now),
        LearningEvent(id: "event-2", kind: .rerolled(recipe: "upma", slot: .breakfast, reason: .tooLong), at: now),
        LearningEvent(id: "event-3", kind: .rerolled(recipe: "upma", slot: .breakfast, reason: nil), at: now),
        LearningEvent(id: "event-4", kind: .skipped(recipe: "dal-tadka", slot: .dinner), at: later),
        LearningEvent(id: "event-5", kind: .cooked(recipe: "dal-tadka"), at: later),
        LearningEvent(id: "event-6", kind: .importedItem(ingredient: "rice"), at: later),
        LearningEvent(
            id: "event-7",
            kind: .reflectBackAnswered(
                key: FactKey(subject: .household, statement: .prefersQuickWeekday), answer: .dontAskAgain),
            at: later),
    ]

    static let promptStates: [PromptState] = [
        PromptState(promptId: "lunchbox", lastShownAt: now, dismissedAt: later),
        PromptState(promptId: "reflect-back", answeredAt: later),
        PromptState(promptId: "never-shown"),
    ]

    static let report = ValidationReport(
        planId: "plan-2", contentHash: "abc123",
        violations: [
            Violation(mealId: "meal-1", memberId: childID, kind: .excludedTag(.milk, ingredient: "ghee")),
            Violation(mealId: "meal-1", memberId: adultID, kind: .unverifiedIngredient("hing")),
            Violation(mealId: "meal-2", memberId: childID, kind: .unknownRecipe("missing")),
            Violation(mealId: "meal-1", memberId: childID, kind: .unknownIngredient("ghost")),
        ])
}
