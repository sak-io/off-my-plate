import OMPDomain

/// The raw recipe and ingredient data the validator checks a plan against (ADR 0007).
///
/// Built from plain `[Recipe]` and `[Ingredient]` arrays (for example `SeedLibrary.recipes`
/// and `SeedLibrary.ingredients`), so `OMPSafetyCheck` depends on `OMPDomain` only and never
/// shares code with the planner's precomputed tag index. Only the raw ingredient lines and the
/// ingredient taxonomy are kept; `Recipe.declaredTags` is deliberately ignored.
///
/// Duplicate ids are merged conservatively, so a duplicate can never weaken a check:
/// - two ingredients with the same id: their `tags` and `mayContain` are unioned, and the
///   result is unverified if either is;
/// - two recipes with the same id: their ingredient lines are concatenated.
public struct SafetyCheckLibrary: Sendable, Hashable {
    /// What the validator knows about one ingredient.
    struct IngredientFacts: Sendable, Hashable {
        /// `tags` and `mayContain` together: "may contain" counts as "contains".
        var containedTags: Set<FoodTag>
        var isUnverified: Bool
    }

    /// Each recipe's ingredient ids in line order (optional lines included).
    let recipeLines: [RecipeID: [IngredientID]]
    let ingredientFacts: [IngredientID: IngredientFacts]

    public init(recipes: [Recipe], ingredients: [Ingredient]) {
        var facts: [IngredientID: IngredientFacts] = [:]
        for ingredient in ingredients {
            let contained = ingredient.tags.union(ingredient.mayContain)
            let unverified = ingredient.tagStatus != .verified
            if var existing = facts[ingredient.id] {
                existing.containedTags.formUnion(contained)
                existing.isUnverified = existing.isUnverified || unverified
                facts[ingredient.id] = existing
            } else {
                facts[ingredient.id] = IngredientFacts(containedTags: contained, isUnverified: unverified)
            }
        }

        var lines: [RecipeID: [IngredientID]] = [:]
        for recipe in recipes {
            lines[recipe.id, default: []].append(contentsOf: recipe.ingredients.map(\.ingredientId))
        }

        self.recipeLines = lines
        self.ingredientFacts = facts
    }
}
