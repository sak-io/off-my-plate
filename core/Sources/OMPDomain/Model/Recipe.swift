/// The meal types a recipe can be cooked for. Lunchbox suitability is a separate flag
/// (`Recipe.lunchboxSuitable`), because a lunchbox is a slot, not a kind of dish.
public enum MealType: String, CaseIterable, Codable, Sendable, Hashable {
    case breakfast
    case lunch
    case dinner
    case snack
}

/// One ingredient line of a recipe.
public struct RecipeIngredientLine: Codable, Sendable, Hashable {
    public var ingredientId: IngredientID
    /// Amount in `unit` for the recipe's `servings`. Ignored for non-quantified units.
    public var quantity: Double
    public var unit: MeasureUnit
    /// An optional garnish or extra. Its tags still count for safety (seed validator, T04).
    public var isOptional: Bool

    public init(ingredientId: IngredientID, quantity: Double, unit: MeasureUnit, isOptional: Bool = false) {
        self.ingredientId = ingredientId
        self.quantity = quantity
        self.unit = unit
        self.isOptional = isOptional
    }
}

/// Where a recipe came from (G1: provenance recorded per recipe).
public struct RecipeProvenance: Codable, Sendable, Hashable {
    /// Who wrote or adapted it, for example "OffMyPlate team (original)".
    public var source: String
    public var notes: String?

    public init(source: String, notes: String? = nil) {
        self.source = source
        self.notes = notes
    }
}

/// Human sign-off state of a seed recipe's tags (G1, task T06).
public enum RecipeReviewStatus: String, CaseIterable, Codable, Sendable, Hashable {
    case draft
    case signedOff
}

/// The human review record of a seed recipe.
public struct RecipeReview: Codable, Sendable, Hashable {
    public var status: RecipeReviewStatus
    public var reviewer: String?
    public var reviewedOn: LocalDate?

    public init(status: RecipeReviewStatus, reviewer: String? = nil, reviewedOn: LocalDate? = nil) {
        self.status = status
        self.reviewer = reviewer
        self.reviewedOn = reviewedOn
    }
}

/// A seed recipe (plan section 3.1; content in ADR 0010). The schema details are owned by T04.
public struct Recipe: Identifiable, Codable, Sendable, Hashable {
    public let id: RecipeID
    public var title: String
    /// Cuisine/region from the catalog, used for cuisine-affinity scoring.
    public var region: CuisineID
    public var mealTypes: Set<MealType>
    public var lunchboxSuitable: Bool
    /// The number of adult portions the quantities are written for.
    public var servings: Int
    public var prepMinutes: Int
    public var cookMinutes: Int
    public var ingredients: [RecipeIngredientLine]
    public var steps: [String]
    /// Tags declared by the author; the seed validator checks they equal the tags derived
    /// from the ingredients (T04). Safety checks never trust them alone (ADR 0007).
    public var declaredTags: Set<FoodTag>
    public var provenance: RecipeProvenance
    public var review: RecipeReview

    public init(
        id: RecipeID,
        title: String,
        region: CuisineID,
        mealTypes: Set<MealType>,
        lunchboxSuitable: Bool = false,
        servings: Int,
        prepMinutes: Int,
        cookMinutes: Int,
        ingredients: [RecipeIngredientLine],
        steps: [String],
        declaredTags: Set<FoodTag>,
        provenance: RecipeProvenance,
        review: RecipeReview
    ) {
        self.id = id
        self.title = title
        self.region = region
        self.mealTypes = mealTypes
        self.lunchboxSuitable = lunchboxSuitable
        self.servings = servings
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.ingredients = ingredients
        self.steps = steps
        self.declaredTags = declaredTags
        self.provenance = provenance
        self.review = review
    }

    /// Total time in minutes.
    public var totalMinutes: Int {
        prepMinutes + cookMinutes
    }
}
