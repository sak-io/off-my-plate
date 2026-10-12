import Foundation
import OMPDomain
import OMPRecipes
import Testing

/// The production seed shipped in `Resources/seed/`, read through `Bundle.module` (this suite
/// runs on Linux CI, so it also proves the resource lookup works with swift-corelibs-foundation).
@Suite("Bundled seed library")
struct BundledSeedTests {
    @Test("the bundled files load from Bundle.module and pass the validator")
    func loadsAndValidates() throws {
        let files = try SeedLoader.bundledFiles()
        let result = SeedValidator.validate(files)
        #expect(result.issues == [], "\(result.issues.map(\.description).joined(separator: "\n"))")
        let library = try SeedLoader.loadBundled()
        #expect(!library.contentVersion.isEmpty)
        #expect(!library.ingredients.isEmpty)
        #expect(!library.recipes.isEmpty)
        #expect(library.recipes.contains { $0.lunchboxSuitable })
    }

    @Test("restriction chips are the AC-2.5 list, in display order")
    func chipList() throws {
        let catalog = try SeedLoader.loadBundled().catalog
        let ids: [RestrictionID] = [
            "peanuts", "tree-nuts", "milk", "egg", "wheat-gluten", "soy", "sesame", "mustard", "fish", "shellfish",
            "beef", "pork", "vegetarian", "jain",
        ]
        #expect(catalog.restrictions.map(\.id) == ids)
        for restriction in catalog.restrictions {
            #expect(restriction.labelKey.hasPrefix("restriction."))
        }
    }

    @Test("R4: vegetarian excludes egg and all meat and fish")
    func vegetarian() throws {
        let catalog = try SeedLoader.loadBundled().catalog
        let vegetarian = try #require(catalog.restriction("vegetarian"))
        #expect(vegetarian.excludedTags == [.egg, .fish, .shellfish, .beef, .pork, .poultry, .otherMeat, .gelatin])
    }

    @Test("R4: Jain is vegetarian plus root vegetables, onion, garlic and mushroom")
    func jain() throws {
        let catalog = try SeedLoader.loadBundled().catalog
        let vegetarian = try #require(catalog.restriction("vegetarian"))
        let jain = try #require(catalog.restriction("jain"))
        #expect(jain.excludedTags == vegetarian.excludedTags.union([.rootVegetable, .onion, .garlic, .mushroom]))
    }

    @Test("R4: the keyword 'nuts' selects both peanuts and tree nuts")
    func nutsKeyword() throws {
        let catalog = try SeedLoader.loadBundled().catalog
        #expect(catalog.restrictions(forKeyword: "nuts").map(\.id) == ["peanuts", "tree-nuts"])
        #expect(catalog.restrictions(forKeyword: "groundnut").map(\.id) == ["peanuts"])
        #expect(catalog.restrictions(forKeyword: "Dairy").map(\.id) == ["milk"])
    }

    @Test("wheat/gluten is one chip that excludes both tags")
    func wheatGluten() throws {
        let catalog = try SeedLoader.loadBundled().catalog
        let wheatGluten = try #require(catalog.restriction("wheat-gluten"))
        #expect(wheatGluten.excludedTags == [.wheat, .gluten])
    }

    @Test("every food tag is excluded by at least one restriction")
    func everyTagCovered() throws {
        let catalog = try SeedLoader.loadBundled().catalog
        let covered = catalog.restrictions.reduce(into: Set<FoodTag>()) { $0.formUnion($1.excludedTags) }
        #expect(covered == Set(FoodTag.allCases))
    }

    @Test("R4: hing counts as wheat and gluten")
    func hing() throws {
        let library = try SeedLoader.loadBundled()
        let hing = try #require(library.ingredient("hing"))
        #expect(hing.tags.union(hing.mayContain).isSuperset(of: [.wheat, .gluten]))
    }

    @Test("AC-10.3: the catalog defines every aisle with a label, in display order")
    func aisles() throws {
        let catalog = try SeedLoader.loadBundled().catalog
        #expect(catalog.aisles == Aisle.allCases)
        for aisle in Aisle.allCases {
            #expect(catalog.aisleLabelKeys[aisle] == "aisle.\(aisle.rawValue)")
        }
        for tag in FoodTag.allCases {
            #expect(catalog.foodTagLabelKeys[tag] == "foodTag.\(tag.rawValue)")
        }
    }

    @Test("every bundled recipe's region is a catalog cuisine")
    func regions() throws {
        let library = try SeedLoader.loadBundled()
        let cuisines = Set(library.catalog.cuisines.map(\.id))
        for recipe in library.recipes {
            #expect(cuisines.contains(recipe.region), "\(recipe.id)")
        }
    }
}
