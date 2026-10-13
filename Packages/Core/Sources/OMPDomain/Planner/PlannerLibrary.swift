/// The planner's precomputed view of the recipe library (plan section 5 step 1, ADR 0009).
///
/// Built from plain `[Recipe]` and `[Ingredient]` arrays (for example `SeedLibrary.recipes` and
/// `SeedLibrary.ingredients`), because `OMPDomain` cannot depend on `OMPRecipes`. This is the
/// planner's own tag index; the independent `PlanValidator` (OMPSafetyCheck) recomputes the
/// same facts on a separate code path and never reads this type (ADR 0007).
///
/// Safety semantics (identical to the validator's):
/// - a recipe's tags are the union of `tags` and `mayContain` of every ingredient line,
///   optional lines included; `Recipe.declaredTags` is never read;
/// - a recipe is "unverified" when any line's ingredient has `tagStatus != .verified`;
/// - a line whose ingredient is missing from `ingredients` makes the recipe unplannable for
///   everyone (fail closed: nothing is known about it).
///
/// Duplicate ids are merged conservatively so a duplicate can never weaken a check:
/// duplicate ingredients union their tags (unverified if either is); duplicate recipes
/// concatenate their lines, intersect their meal types and are lunchbox-suitable only if every
/// copy is.
public struct PlannerLibrary: Sendable, Hashable {
    /// What the planner knows about one recipe.
    public struct Entry: Sendable, Hashable {
        public let id: RecipeID
        public let mealTypes: Set<MealType>
        public let lunchboxSuitable: Bool
        /// Ingredient `tags` ∪ `mayContain` over every line, optional lines included.
        public let containedTags: Set<FoodTag>
        /// Some line uses an ingredient whose tags are not verified (AC-4.3).
        public let hasUnverifiedIngredient: Bool
        /// Some line uses an ingredient missing from the taxonomy (fail closed).
        public let hasUnknownIngredient: Bool
    }

    /// Version of the content the plan is made from; copied into `MealPlan.contentVersion`.
    public let contentVersion: String
    /// Every recipe, sorted by id (a fixed iteration order keeps the planner deterministic).
    public let entries: [Entry]

    public init(recipes: [Recipe], ingredients: [Ingredient], contentVersion: String) {
        var facts: [IngredientID: (tags: Set<FoodTag>, unverified: Bool)] = [:]
        for ingredient in ingredients {
            let contained = ingredient.tags.union(ingredient.mayContain)
            let unverified = ingredient.tagStatus != .verified
            if let existing = facts[ingredient.id] {
                facts[ingredient.id] = (existing.tags.union(contained), existing.unverified || unverified)
            } else {
                facts[ingredient.id] = (contained, unverified)
            }
        }

        var byID: [RecipeID: Entry] = [:]
        for recipe in recipes {
            var tags = Set<FoodTag>()
            var unverified = false
            var unknown = false
            for line in recipe.ingredients {
                guard let fact = facts[line.ingredientId] else {
                    unknown = true
                    continue
                }
                tags.formUnion(fact.tags)
                unverified = unverified || fact.unverified
            }
            if let existing = byID[recipe.id] {
                byID[recipe.id] = Entry(
                    id: recipe.id,
                    mealTypes: existing.mealTypes.intersection(recipe.mealTypes),
                    lunchboxSuitable: existing.lunchboxSuitable && recipe.lunchboxSuitable,
                    containedTags: existing.containedTags.union(tags),
                    hasUnverifiedIngredient: existing.hasUnverifiedIngredient || unverified,
                    hasUnknownIngredient: existing.hasUnknownIngredient || unknown)
            } else {
                byID[recipe.id] = Entry(
                    id: recipe.id, mealTypes: recipe.mealTypes, lunchboxSuitable: recipe.lunchboxSuitable,
                    containedTags: tags, hasUnverifiedIngredient: unverified, hasUnknownIngredient: unknown)
            }
        }

        self.contentVersion = contentVersion
        self.entries = byID.values.sorted { $0.id < $1.id }
    }

    /// The entry for `id`, if the library has that recipe.
    public func entry(_ id: RecipeID) -> Entry? {
        entries.first { $0.id == id }
    }
}
