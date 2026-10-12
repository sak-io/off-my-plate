import Foundation
import OMPDomain

/// A cuisine/region from the catalog (S-03 chips, cuisine-affinity scoring).
public struct CatalogCuisine: Identifiable, Sendable, Hashable {
    public let id: CuisineID
    /// String Catalog key for the chip label; the UI localises it.
    public let labelKey: String

    public init(id: CuisineID, labelKey: String) {
        self.id = id
        self.labelKey = labelKey
    }
}

/// The validated `catalog.json`: tag and aisle labels, cuisines, the safety-screen restriction
/// chips (AC-2.5) and the keywords that map typed or spoken words to restrictions (plan R4).
public struct SeedCatalog: Sendable, Hashable {
    /// String Catalog key per food tag. Every `FoodTag` has one.
    public let foodTagLabelKeys: [FoodTag: String]
    /// String Catalog key per aisle. Every `Aisle` has one.
    public let aisleLabelKeys: [Aisle: String]
    /// Cuisines in chip order.
    public let cuisines: [CatalogCuisine]
    /// Restriction chips in display order (AC-2.5). Their tag sets are the R4 definitions.
    public let restrictions: [Restriction]
    /// Lowercased keyword -> restrictions it selects. One keyword may select several
    /// restrictions ("nuts" selects peanuts and tree nuts, R4).
    public let restrictionKeywords: [String: [RestrictionID]]

    /// Shopping-list aisles in display order (AC-10.3). The validator requires the catalog to
    /// list them in `Aisle.allCases` order, so there is one source of truth for the order.
    public var aisles: [Aisle] {
        Aisle.allCases
    }

    /// The restriction with `id`.
    public func restriction(_ id: RestrictionID) -> Restriction? {
        restrictions.first { $0.id == id }
    }

    /// The restrictions a typed or spoken keyword selects, in chip order. Matching ignores
    /// case and surrounding whitespace; an unknown keyword selects nothing.
    public func restrictions(forKeyword text: String) -> [Restriction] {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let ids = restrictionKeywords[key] else { return [] }
        let wanted = Set(ids)
        return restrictions.filter { wanted.contains($0.id) }
    }
}

/// The validated, read-only seed library (ADR 0010). Only `SeedValidator` creates one, so every
/// recipe line resolves to an ingredient and every `declaredTags` equals the derived tags.
public struct SeedLibrary: Sendable, Hashable {
    /// Shared by all three files; each plan records it (plan section 3.2).
    public let contentVersion: String
    public let catalog: SeedCatalog
    /// In file order.
    public let ingredients: [Ingredient]
    /// In file order.
    public let recipes: [Recipe]

    private let ingredientIndex: [IngredientID: Int]
    private let recipeIndex: [RecipeID: Int]

    init(contentVersion: String, catalog: SeedCatalog, ingredients: [Ingredient], recipes: [Recipe]) {
        self.contentVersion = contentVersion
        self.catalog = catalog
        self.ingredients = ingredients
        self.recipes = recipes
        var ingredientIndex: [IngredientID: Int] = [:]
        for (index, ingredient) in ingredients.enumerated() {
            ingredientIndex[ingredient.id] = index
        }
        var recipeIndex: [RecipeID: Int] = [:]
        for (index, recipe) in recipes.enumerated() {
            recipeIndex[recipe.id] = index
        }
        self.ingredientIndex = ingredientIndex
        self.recipeIndex = recipeIndex
    }

    /// The ingredient with `id`.
    public func ingredient(_ id: IngredientID) -> Ingredient? {
        ingredientIndex[id].map { ingredients[$0] }
    }

    /// The recipe with `id`.
    public func recipe(_ id: RecipeID) -> Recipe? {
        recipeIndex[id].map { recipes[$0] }
    }

    /// The recipe's derived tags: the union of `tags` and `mayContain` of every ingredient,
    /// optional lines included. "May contain" counts as "contains" for safety (ADR 0007), so
    /// this is the set a hard rule's excluded tags must be disjoint from.
    public func derivedTags(of recipe: Recipe) -> Set<FoodTag> {
        var tags = Set<FoodTag>()
        for line in recipe.ingredients {
            guard let ingredient = ingredient(line.ingredientId) else { continue }
            tags.formUnion(ingredient.tags)
            tags.formUnion(ingredient.mayContain)
        }
        return tags
    }

    /// The recipe's ingredients whose tags are `unverified` (AC-4.3), in line order.
    public func unverifiedIngredients(of recipe: Recipe) -> [Ingredient] {
        var seen = Set<IngredientID>()
        var result: [Ingredient] = []
        for line in recipe.ingredients {
            guard let ingredient = ingredient(line.ingredientId), ingredient.tagStatus == .unverified,
                seen.insert(ingredient.id).inserted
            else { continue }
            result.append(ingredient)
        }
        return result
    }
}

/// Reads the seed files bundled with `OMPRecipes` (`Bundle.module`, which also works on Linux).
public enum SeedLoader {
    /// The bundled seed files, unvalidated.
    public static func bundledFiles() throws -> SeedFiles {
        SeedFiles(
            catalog: try bundledData(.catalog),
            ingredients: try bundledData(.ingredients),
            recipes: try bundledData(.recipes))
    }

    /// Reads and validates the bundled seed library.
    /// - Throws: `SeedLoadError.resourceMissing` or `SeedLoadError.invalid`.
    public static func loadBundled() throws -> SeedLibrary {
        try load(bundledFiles())
    }

    /// Validates `files` and returns the library.
    /// - Throws: `SeedLoadError.invalid` with every issue found.
    public static func load(_ files: SeedFiles) throws -> SeedLibrary {
        let result = SeedValidator.validate(files)
        guard let library = result.library else { throw SeedLoadError.invalid(result.issues) }
        return library
    }

    private static func bundledData(_ file: SeedFile) throws -> Data {
        guard let url = bundledURL(file) else { throw SeedLoadError.resourceMissing(file) }
        return try Data(contentsOf: url)
    }

    private static func bundledURL(_ file: SeedFile) -> URL? {
        let bundle = Bundle.module
        if let url = bundle.url(forResource: file.resourceName, withExtension: "json", subdirectory: "seed") {
            return url
        }
        // Fallback for bundle layouts where the lookup above misses a copied directory.
        guard let base = bundle.resourceURL else { return nil }
        let url = base.appendingPathComponent("seed", isDirectory: true)
            .appendingPathComponent(file.rawValue, isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
