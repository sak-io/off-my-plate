import Foundation
import OMPDomain
import Testing

/// Ingredients, recipes, plans and pantry items for the pantry and shopping tests (T14).
///
/// Every plan uses `PlanFixture` servings: adult 1.0 + child 0.6 = 1.6 portions, so a
/// 4-serving recipe is scaled by 0.4 and a 2-serving recipe by 0.8.
enum ShoppingFixture {
    static let utc = TimeZone(secondsFromGMT: 0)!
    /// 2026-10-12T00:00:00Z, the plan's first day (`Sample.monday`).
    static let now = Sample.now
    static let today = Sample.monday
    static let day: TimeInterval = 86_400

    static func ingredient(
        _ id: IngredientID, _ name: String, aisle: Aisle, unit: MeasureUnit, gramsPerMl: Double? = nil,
        gramsPerPiece: Double? = nil, location: StorageLocation = .shelf, fridgeDays: Int? = nil
    ) -> Ingredient {
        Ingredient(
            id: id, name: name, tagStatus: .verified, aisle: aisle, defaultUnit: unit, gramsPerMl: gramsPerMl,
            gramsPerPiece: gramsPerPiece, defaultLocation: location, fridgeShelfLifeDays: fridgeDays)
    }

    static let ingredientList: [Ingredient] = [
        ingredient("toor-dal", "Toor dal", aisle: .pulsesAndLentils, unit: .gram),
        ingredient("ghee", "Ghee", aisle: .oilsAndGhee, unit: .tablespoon, gramsPerMl: 0.91),
        ingredient("onion", "Onion", aisle: .vegetablesAndFruit, unit: .piece, gramsPerPiece: 150),
        ingredient("salt", "Salt", aisle: .spicesAndMasalas, unit: .toTaste),
        ingredient("rice", "Rice", aisle: .grainsAndFlours, unit: .gram),
        ingredient("coriander", "Coriander", aisle: .vegetablesAndFruit, unit: .piece),
        ingredient("milk", "Milk", aisle: .dairyAndEggs, unit: .millilitre, location: .fridge, fridgeDays: 5),
        ingredient("paneer", "Paneer", aisle: .dairyAndEggs, unit: .gram, location: .fridge, fridgeDays: 4),
    ]
    static let ingredients = Dictionary(uniqueKeysWithValues: ingredientList.map { ($0.id, $0) })

    static func recipe(_ id: RecipeID, servings: Int, _ lines: [RecipeIngredientLine]) -> Recipe {
        Recipe(
            id: id, title: id.rawValue, region: "northIndian", mealTypes: [.lunch, .dinner], servings: servings,
            prepMinutes: 10, cookMinutes: 20, ingredients: lines, steps: ["Cook."], declaredTags: [],
            provenance: RecipeProvenance(source: "test"), review: RecipeReview(status: .signedOff))
    }

    static func line(_ id: IngredientID, _ quantity: Double, _ unit: MeasureUnit) -> RecipeIngredientLine {
        RecipeIngredientLine(ingredientId: id, quantity: quantity, unit: unit)
    }

    /// Per meal (x 0.4): toor dal 80 g, ghee 0.8 tbsp (12 ml), onion 0.8 piece.
    static let dalTadka = recipe(
        "dal-tadka", servings: 4,
        [line("toor-dal", 200, .gram), line("ghee", 2, .tablespoon), line("salt", 0, .toTaste), line("onion", 2, .piece)])
    /// Per meal (x 0.8): rice 200 g, coriander 8 g, onion 80 g.
    static let rajmaChawal = recipe(
        "rajma-chawal", servings: 2, [line("rice", 250, .gram), line("coriander", 10, .gram), line("onion", 100, .gram)])
    /// Per meal (x 0.4): paneer 80 g, milk 40 ml, coriander 0.4 piece.
    static let palakPaneer = recipe(
        "palak-paneer", servings: 4, [line("paneer", 200, .gram), line("milk", 100, .millilitre), line("coriander", 1, .piece)])

    static let recipes: [RecipeID: Recipe] = [
        dalTadka.id: dalTadka, rajmaChawal.id: rajmaChawal, palakPaneer.id: palakPaneer,
    ]

    /// An approved plan of `meals` (approved through the lifecycle, so the hash is genuine).
    static func approved(_ meals: [PlannedMeal]) throws -> MealPlan {
        try PlanFixture.approved(PlanFixture.draft(meals: meals))
    }

    static func dalPlan() throws -> MealPlan {
        try approved([PlanFixture.meal("meal-1", day: 0, recipe: "dal-tadka")])
    }

    static func pantry(
        _ id: PantryItemID, _ ingredient: IngredientID?, _ quantity: Double, _ unit: MeasureUnit,
        location: StorageLocation = .shelf, expiresOn: LocalDate? = nil, confirmedDaysAgo: Double = 0,
        freeText: String = "something"
    ) -> PantryItem {
        PantryItem(
            id: id, item: ingredient.map(PantryItemRef.ingredient) ?? .freeText(freeText), quantity: quantity,
            unit: unit, location: location, expiresOn: expiresOn,
            lastConfirmedAt: now.addingTimeInterval(-confirmedDaysAgo * day), source: .manual)
    }

    static func derive(_ plan: MealPlan, pantry: [PantryItem] = [], now: Date = ShoppingFixture.now) -> [DerivedShoppingLine] {
        ShoppingDerivation.derive(
            plan: plan, recipes: recipes, ingredients: ingredients, pantry: pantry, now: now, timeZone: utc)
    }

    static func approx(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= 1e-9 * max(1, abs(lhs), abs(rhs))
    }

    /// The line with `key`, if any.
    static func find(_ lines: [DerivedShoppingLine], _ key: String) -> DerivedShoppingLine? {
        lines.first { $0.key == key }
    }

    /// Whether `line` holds `amount` of `unit`.
    static func holds(_ line: DerivedShoppingLine?, _ amount: Double, _ unit: MeasureUnit) -> Bool {
        guard let line else { return false }
        return line.quantity.unit == unit && approx(line.quantity.amount, amount)
    }

    /// The error a Mark cooked call throws, or nil. Untyped on purpose (see `PlanFixture.error`).
    static func cookError<T>(_ body: () throws -> T) -> MarkCookedError? {
        do {
            _ = try body()
            return nil
        } catch let error as MarkCookedError {
            return error
        } catch {
            Issue.record("unexpected error: \(error)")
            return nil
        }
    }
}
