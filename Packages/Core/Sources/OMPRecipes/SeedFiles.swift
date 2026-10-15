import Foundation

/// The three seed files (ADR 0010). They live in `Resources/seed/` and are bundled with
/// `.copy`, so the bundle keeps the `seed/` directory.
public enum SeedFile: String, CaseIterable, Sendable, Hashable {
    case catalog = "catalog.json"
    case ingredients = "ingredients.json"
    case recipes = "recipes.json"

    /// The file name without the `.json` extension.
    var resourceName: String {
        switch self {
        case .catalog: return "catalog"
        case .ingredients: return "ingredients"
        case .recipes: return "recipes"
        }
    }
}

/// The raw bytes of one set of seed files: the bundled ones (`SeedLoader.bundledFiles()`) or
/// test fixtures. Nothing is trusted until `SeedValidator.validate(_:)` has accepted it.
public struct SeedFiles: Sendable, Hashable {
    public var catalog: Data
    public var ingredients: Data
    public var recipes: Data

    public init(catalog: Data, ingredients: Data, recipes: Data) {
        self.catalog = catalog
        self.ingredients = ingredients
        self.recipes = recipes
    }

    /// The bytes of `file`.
    public subscript(file: SeedFile) -> Data {
        switch file {
        case .catalog: return catalog
        case .ingredients: return ingredients
        case .recipes: return recipes
        }
    }
}

// MARK: - Schema v1 documents
//
// The seed JSON is decoded into these permissive documents first: every field is optional and
// every enumerated value is a plain string. That lets `SeedValidator` report a missing aisle,
// an unknown unit or an unknown tag as a precise `SeedIssue` instead of failing the whole
// decode. Only a validated document becomes a domain `Ingredient`/`Recipe`.
//
// Schema v1 (all three files carry `schemaVersion: 1` and the same `contentVersion`):
//   catalog.json      { foodTags: [{id, labelKey}], aisles: [{id, labelKey}] (display order),
//                       cuisines: [{id, labelKey}], restrictions: [{id, labelKey, excludedTags}]
//                       (chip order), restrictionKeywords: {keyword: [restrictionId]} }
//   ingredients.json  { ingredients: [{id, name, synonyms?, tags, mayContain?, tagStatus, aisle,
//                       defaultUnit, gramsPerMl?, gramsPerPiece?, defaultLocation,
//                       fridgeShelfLifeDays?}] }
//   recipes.json      { recipes: [{id, title, region, mealTypes, lunchboxSuitable?, servings,
//                       prepMinutes, cookMinutes, ingredients: [{ingredientId, quantity?, unit,
//                       optional?}], steps, declaredTags, provenance: {source, notes?},
//                       review: {status, reviewer?, reviewedOn?}}] }

struct LabelledEntryDocument: Decodable {
    var id: String?
    var labelKey: String?
}

struct RestrictionDocument: Decodable {
    var id: String?
    var labelKey: String?
    var excludedTags: [String]?
}

struct CatalogDocument: Decodable {
    var schemaVersion: Int?
    var contentVersion: String?
    var foodTags: [LabelledEntryDocument]?
    var aisles: [LabelledEntryDocument]?
    var cuisines: [LabelledEntryDocument]?
    var restrictions: [RestrictionDocument]?
    var restrictionKeywords: [String: [String]]?
}

struct IngredientDocument: Decodable {
    var id: String?
    var name: String?
    var synonyms: [String]?
    var tags: [String]?
    var mayContain: [String]?
    var tagStatus: String?
    var aisle: String?
    var defaultUnit: String?
    var gramsPerMl: Double?
    var gramsPerPiece: Double?
    var defaultLocation: String?
    var fridgeShelfLifeDays: Int?
}

struct IngredientsDocument: Decodable {
    var schemaVersion: Int?
    var contentVersion: String?
    var ingredients: [IngredientDocument]?
}

struct RecipeLineDocument: Decodable {
    var ingredientId: String?
    var quantity: Double?
    var unit: String?
    var optional: Bool?
}

struct ProvenanceDocument: Decodable {
    var source: String?
    var notes: String?
}

struct ReviewDocument: Decodable {
    var status: String?
    var reviewer: String?
    var reviewedOn: String?
}

struct RecipeDocument: Decodable {
    var id: String?
    var title: String?
    var region: String?
    var mealTypes: [String]?
    var lunchboxSuitable: Bool?
    var servings: Int?
    var prepMinutes: Int?
    var cookMinutes: Int?
    var ingredients: [RecipeLineDocument]?
    var steps: [String]?
    var declaredTags: [String]?
    var provenance: ProvenanceDocument?
    var review: ReviewDocument?
}

struct RecipesDocument: Decodable {
    var schemaVersion: Int?
    var contentVersion: String?
    var recipes: [RecipeDocument]?
}
