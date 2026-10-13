import Foundation

/// What one ingredient is needed for: its running total across meals (AC-6.4, AC-10.1).
public struct IngredientRequirement: Sendable, Hashable {
    public let ingredientId: IngredientID
    /// Non-convertible amounts stay separate parts (AC-10.1).
    public var total: QuantityTotal

    public init(ingredientId: IngredientID, total: QuantityTotal) {
        self.ingredientId = ingredientId
        self.total = total
    }
}

/// Requirements arithmetic over plans and recipes (plan section 6, task T14).
///
/// Recipes and ingredients are passed as plain dictionaries so this stays independent of the
/// recipe library. A missing ingredient entry only loses cross-dimension conversion.
public enum IngredientRequirements {
    /// The conversion profile of `id`, or same-dimension only when the ingredient is unknown.
    static func profile(_ id: IngredientID, in ingredients: [IngredientID: Ingredient]) -> ConversionProfile {
        ingredients[id].map(ConversionProfile.init(ingredient:)) ?? .sameDimensionOnly
    }

    /// AC-6.4: the sum of the eating members' portions (adult = 1.0). Negative, NaN and
    /// infinite portions count as 0.
    public static func portionSum(of meal: PlannedMeal) -> Double {
        meal.servings
            .filter { !$0.notEating && $0.portion.isFinite && $0.portion > 0 }
            .reduce(0) { $0 + $1.portion }
    }

    /// The quantified lines of `recipe` scaled to `meal`: quantity × Σportion / recipe.servings
    /// (AC-6.4). Non-quantified lines ("pinch", "to taste") are left out: they are never on
    /// the shopping list and never deducted. Optional lines are included (see handoff Q1).
    /// A recipe with fewer than 1 serving is treated as 1 serving (the seed validator forbids it).
    public static func scaledLines(of recipe: Recipe, for meal: PlannedMeal) -> [(IngredientID, Quantity)] {
        let factor = portionSum(of: meal) / Double(max(1, recipe.servings))
        return recipe.ingredients.compactMap { line -> (IngredientID, Quantity)? in
            let quantity = Quantity(line.quantity, line.unit)
            guard quantity.isQuantified else { return nil }
            return (line.ingredientId, quantity.scaled(by: factor))
        }
    }

    /// Sums `meals`' scaled recipe lines per ingredient. Meals with no recipe, or whose recipe
    /// is missing from `recipes`, contribute nothing. Sorted by ingredient id.
    public static func totals(
        of meals: [PlannedMeal],
        recipes: [RecipeID: Recipe],
        ingredients: [IngredientID: Ingredient]
    ) -> [IngredientRequirement] {
        var totals: [IngredientID: QuantityTotal] = [:]
        for meal in meals {
            guard let recipeId = meal.recipeId, let recipe = recipes[recipeId] else { continue }
            for (ingredientId, quantity) in scaledLines(of: recipe, for: meal) {
                var total = totals[ingredientId] ?? QuantityTotal(profile: profile(ingredientId, in: ingredients))
                total.add(quantity)
                totals[ingredientId] = total
            }
        }
        return totals
            .map { IngredientRequirement(ingredientId: $0.key, total: $0.value) }
            .sorted { $0.ingredientId.rawValue.utf8.lexicographicallyPrecedes($1.ingredientId.rawValue.utf8) }
    }

    /// The meals a shopping list is derived from (AC-5.3, AC-10.1, AC-10.2, R1): the
    /// effectively-approved plan's usable meals (not blocked by safety) that are not cooked
    /// yet, have a recipe and are dated `today` or later. Empty for any other plan.
    public static func shoppingMeals(of plan: MealPlan, today: LocalDate) -> [PlannedMeal] {
        plan.usableApprovedMeals.filter { $0.cooked == nil && !$0.isEmpty && $0.date >= today }
    }

    /// AC-10.1: Σ over the shopping meals of qty × Σportion / recipe.servings, per ingredient.
    /// Empty for a plan that is not effectively approved (AC-5.3).
    public static func forShopping(
        plan: MealPlan,
        recipes: [RecipeID: Recipe],
        ingredients: [IngredientID: Ingredient],
        today: LocalDate
    ) -> [IngredientRequirement] {
        totals(of: shoppingMeals(of: plan, today: today), recipes: recipes, ingredients: ingredients)
    }
}

/// Display normalisation of shopping quantities (AC-6.4 "unit-normalised").
public enum ShoppingUnits {
    /// The base unit a requirement part is shown in, chosen so it does not depend on the order
    /// the meals were summed in: the base unit of the ingredient's default unit if the part
    /// converts to it, otherwise the first of g, ml, piece it converts to.
    public static func displayBaseUnit(
        for part: Quantity, profile: ConversionProfile, defaultUnit: MeasureUnit?
    ) -> MeasureUnit? {
        var candidates: [MeasureUnit] = []
        if let base = defaultUnit?.baseUnit { candidates.append(base) }
        candidates += [.gram, .millilitre, .piece]
        return candidates.first { part.converted(to: $0, using: profile) != nil }
    }

    /// `part` in its display unit: the stable base unit, then grams of 1000 or more as kg and
    /// millilitres of 1000 or more as litres. Non-quantified parts are returned unchanged.
    public static func normalised(
        _ part: Quantity, profile: ConversionProfile, defaultUnit: MeasureUnit?
    ) -> Quantity {
        guard let base = displayBaseUnit(for: part, profile: profile, defaultUnit: defaultUnit),
              let inBase = part.converted(to: base, using: profile)
        else { return part.inBaseUnit }
        switch base {
        case .gram where inBase.amount >= 1000: return inBase.converted(to: .kilogram) ?? inBase
        case .millilitre where inBase.amount >= 1000: return inBase.converted(to: .litre) ?? inBase
        default: return inBase
        }
    }
}
