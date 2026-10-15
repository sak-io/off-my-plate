import Foundation
import OMPDomain
import OMPRecipes
import Testing

/// T05: the bundled ingredient taxonomy. Pins the hidden-allergen facts the safety gate relies
/// on (ADR 0007: `mayContain` counts as "contains"; AC-4.3: unverified excludes for any hard
/// rule), so any change to them has to be deliberate.
@Suite("Bundled ingredient taxonomy")
struct IngredientTaxonomyTests {
    private static func library() throws -> SeedLibrary {
        try SeedLoader.loadBundled()
    }

    /// Tags every safety check treats as present.
    private static func effectiveTags(_ ingredient: Ingredient) -> Set<FoodTag> {
        ingredient.tags.union(ingredient.mayContain)
    }

    private static func ingredient(_ id: IngredientID, in library: SeedLibrary) throws -> Ingredient {
        try #require(library.ingredient(id), "missing ingredient \(id)")
    }

    @Test("the full bundled seed passes the validator with about 150 ingredients")
    func validatesWithFullTaxonomy() throws {
        let files = try SeedLoader.bundledFiles()
        let result = SeedValidator.validate(files)
        #expect(result.issues == [], "\(result.issues.map(\.description).joined(separator: "\n"))")
        let library = try #require(result.library)
        #expect(library.ingredients.count >= 150)
    }

    @Test("A5: every name and synonym is unique across the taxonomy (case-insensitive)")
    func everySynonymUnique() throws {
        let library = try Self.library()
        var owners: [String: IngredientID] = [:]
        for ingredient in library.ingredients {
            var ownNames = Set<String>()
            for text in [ingredient.name] + ingredient.synonyms {
                let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                #expect(!key.isEmpty, "\(ingredient.id) has an empty name or synonym")
                #expect(ownNames.insert(key).inserted, "\(ingredient.id) lists '\(key)' twice")
                if let owner = owners[key], owner != ingredient.id {
                    Issue.record("'\(key)' names both \(owner) and \(ingredient.id)")
                }
                owners[key] = ingredient.id
            }
        }
    }

    @Test("A5: common Indian names resolve to the right ingredient")
    func transliterations() throws {
        let library = try Self.library()
        let expected: [(String, IngredientID)] = [
            ("dahi", "curd"), ("curd", "curd"), ("yogurt", "curd"), ("atta", "whole-wheat-flour"),
            ("besan", "besan"), ("gram flour", "besan"), ("jeera", "cumin-seeds"), ("hing", "hing"),
            ("sooji", "semolina"), ("rava", "semolina"), ("maida", "maida"), ("haldi", "turmeric-powder"),
            ("rai", "mustard-seeds"), ("til", "sesame-seeds"), ("kaju", "cashews"), ("moongphali", "peanuts"),
            ("anda", "egg"), ("machli", "fish"), ("doodh", "milk"), ("makhan", "butter"), ("mawa", "khoya"),
            ("pyaz", "onion"), ("lahsun", "garlic"), ("adrak", "ginger"), ("aloo", "potato"),
        ]
        var byName: [String: IngredientID] = [:]
        for ingredient in library.ingredients {
            for text in [ingredient.name] + ingredient.synonyms {
                byName[text.lowercased()] = ingredient.id
            }
        }
        for (name, id) in expected {
            #expect(byName[name] == id, "\(name)")
        }
    }

    @Test("Kerala staples resolve by their Malayalam names")
    func keralaStaples() throws {
        let library = try Self.library()
        var byName: [String: IngredientID] = [:]
        for ingredient in library.ingredients {
            for text in [ingredient.name] + ingredient.synonyms {
                byName[text.lowercased()] = ingredient.id
            }
        }
        let expected: [(String, IngredientID)] = [
            ("thenga", "coconut"), ("velichenna", "coconut-oil"), ("thenga paal", "coconut-milk"),
            ("kudampuli", "malabar-tamarind"), ("kunjulli", "shallots"), ("nendran", "raw-banana"),
            ("kappa", "tapioca"), ("chakka", "raw-jackfruit"), ("kumbalanga", "ash-gourd"), ("chena", "elephant-foot-yam"),
            ("chembu", "colocasia"), ("muringakka", "drumstick"), ("vanpayar", "red-cowpeas"), ("kadala", "kala-chana"),
            ("cherupayar", "whole-moong"), ("rosematta rice", "matta-rice"), ("pachari", "rice"),
            ("puttu podi", "puttu-flour"), ("idiyappam podi", "rice-flour"), ("appam batter", "appam-batter"),
            ("mathi", "sardine"), ("ayala", "mackerel"), ("karimeen", "pearl-spot"), ("meen", "fish"), ("mutta", "egg"),
        ]
        for (name, id) in expected {
            #expect(byName[name] == id, "\(name)")
        }
        for id: IngredientID in ["sardine", "mackerel", "pearl-spot"] {
            #expect(try Self.ingredient(id, in: library).tags.contains(.fish), "\(id)")
        }
        #expect(try Self.ingredient("tapioca", in: library).tags.contains(.rootVegetable))
        #expect(library.catalog.cuisines.map(\.id).contains("kerala"))
    }

    @Test("R4: hing may contain wheat and gluten and is unverified")
    func hing() throws {
        let hing = try Self.ingredient("hing", in: try Self.library())
        #expect(hing.mayContain.isSuperset(of: [.wheat, .gluten]))
        #expect(hing.tagStatus == .unverified)
    }

    @Test("dairy staples carry the milk tag", arguments: [
        "ghee", "paneer", "curd", "butter", "khoya", "milk", "buttermilk", "fresh-cream", "condensed-milk", "cheese",
    ] as [IngredientID])
    func dairyIsMilk(id: IngredientID) throws {
        let ingredient = try Self.ingredient(id, in: try Self.library())
        #expect(ingredient.tags.contains(.milk))
    }

    @Test("non-wheat flours have no wheat tag but may contain wheat and gluten (shared mills)", arguments: [
        "besan", "rice-flour", "ragi-flour", "jowar-flour", "bajra-flour", "maize-flour", "cornflour",
    ] as [IngredientID])
    func sharedMillFlours(id: IngredientID) throws {
        let ingredient = try Self.ingredient(id, in: try Self.library())
        #expect(ingredient.tags.isDisjoint(with: [.wheat, .gluten]))
        #expect(ingredient.mayContain.isSuperset(of: [.wheat, .gluten]))
    }

    @Test("wheat products carry wheat and gluten", arguments: [
        "whole-wheat-flour", "maida", "semolina", "broken-wheat", "vermicelli", "noodles", "bread", "pav", "rusk",
        "soy-sauce",
    ] as [IngredientID])
    func wheatProducts(id: IngredientID) throws {
        let ingredient = try Self.ingredient(id, in: try Self.library())
        #expect(ingredient.tags.isSuperset(of: [.wheat, .gluten]))
    }

    @Test("soy sauce contains soy as well as wheat and gluten, and is unverified")
    func soySauce() throws {
        let soySauce = try Self.ingredient("soy-sauce", in: try Self.library())
        #expect(soySauce.tags.isSuperset(of: [.soy, .wheat, .gluten]))
        #expect(soySauce.tagStatus == .unverified)
    }

    @Test("oats may contain gluten")
    func oats() throws {
        let oats = try Self.ingredient("oats", in: try Self.library())
        #expect(oats.mayContain.contains(.gluten))
    }

    @Test("coconut products are not tagged as tree nuts (owner sign-off item)", arguments: [
        "coconut", "grated-coconut", "dry-coconut", "coconut-milk", "coconut-oil",
    ] as [IngredientID])
    func coconutIsNotTreeNut(id: IngredientID) throws {
        let ingredient = try Self.ingredient(id, in: try Self.library())
        #expect(!Self.effectiveTags(ingredient).contains(.treeNut))
    }

    @Test("oils carry the allergen of their source")
    func oils() throws {
        let library = try Self.library()
        #expect(try Self.ingredient("groundnut-oil", in: library).tags.contains(.peanut))
        #expect(try Self.ingredient("sesame-oil", in: library).tags.contains(.sesame))
        #expect(try Self.ingredient("mustard-oil", in: library).tags.contains(.mustard))
    }

    @Test("nuts and seeds carry their allergen tags")
    func nutsAndSeeds() throws {
        let library = try Self.library()
        for id: IngredientID in ["cashews", "almonds", "pistachios", "walnuts", "chironji"] {
            #expect(try Self.ingredient(id, in: library).tags.contains(.treeNut), "\(id)")
        }
        #expect(try Self.ingredient("peanuts", in: library).tags.contains(.peanut))
        #expect(try Self.ingredient("sesame-seeds", in: library).tags.contains(.sesame))
        #expect(try Self.ingredient("mustard-seeds", in: library).tags.contains(.mustard))
        for id: IngredientID in ["tofu", "soya-chunks"] {
            #expect(try Self.ingredient(id, in: library).tags.contains(.soy), "\(id)")
        }
    }

    @Test("packaged blends, sauces, papad and pickles are unverified", arguments: [
        "garam-masala", "chaat-masala", "sambar-powder", "rasam-powder", "pav-bhaji-masala", "chole-masala",
        "papad", "mango-pickle", "tomato-ketchup", "green-chilli-sauce", "vinegar", "baking-powder", "sev", "chikki",
        "puttu-flour", "appam-batter",
    ] as [IngredientID])
    func packagedIsUnverified(id: IngredientID) throws {
        let ingredient = try Self.ingredient(id, in: try Self.library())
        #expect(ingredient.tagStatus == .unverified)
    }

    @Test("blends that usually contain hing, and papad, may contain wheat and gluten", arguments: [
        "sambar-powder", "rasam-powder", "chaat-masala", "papad",
    ] as [IngredientID])
    func hingBlends(id: IngredientID) throws {
        let ingredient = try Self.ingredient(id, in: try Self.library())
        #expect(ingredient.mayContain.isSuperset(of: [.wheat, .gluten]))
    }

    @Test("ready masalas may contain wheat, gluten, mustard and sesame", arguments: [
        "garam-masala", "biryani-masala", "tandoori-masala",
    ] as [IngredientID])
    func readyMasalas(id: IngredientID) throws {
        let ingredient = try Self.ingredient(id, in: try Self.library())
        #expect(ingredient.mayContain.isSuperset(of: [.wheat, .gluten, .mustard, .sesame]))
        #expect(ingredient.tagStatus == .unverified)
    }

    @Test("hidden sesame and peanut in noodles, papad and chikki")
    func hiddenSesameAndPeanut() throws {
        let library = try Self.library()
        #expect(try Self.ingredient("noodles", in: library).mayContain.contains(.sesame))
        let papad = try Self.ingredient("papad", in: library)
        #expect(papad.mayContain.isSuperset(of: [.sesame, .peanut]))
        let chikki = try Self.ingredient("chikki", in: library)
        #expect(chikki.tags.contains(.peanut))
        #expect(Self.effectiveTags(chikki).contains(.sesame))
        #expect(chikki.tagStatus == .unverified)
    }

    @Test("R4 Jain: onion, garlic, roots and mushroom are tagged")
    func jainTags() throws {
        let library = try Self.library()
        let expected: [(IngredientID, FoodTag)] = [
            ("onion", .onion), ("shallots", .onion), ("spring-onion", .onion), ("garlic", .garlic),
            ("potato", .rootVegetable), ("ginger", .rootVegetable), ("carrot", .rootVegetable),
            ("radish", .rootVegetable), ("beetroot", .rootVegetable), ("sweet-potato", .rootVegetable),
            ("colocasia", .rootVegetable), ("elephant-foot-yam", .rootVegetable), ("mushroom", .mushroom),
        ]
        for (id, tag) in expected {
            #expect(try Self.ingredient(id, in: library).tags.contains(tag), "\(id)")
        }
        let ketchup = try Self.ingredient("tomato-ketchup", in: library)
        #expect(ketchup.mayContain.isSuperset(of: [.onion, .garlic]))
    }

    @Test("R4 vegetarian: egg, meat and fish are tagged")
    func animalTags() throws {
        let library = try Self.library()
        let expected: [(IngredientID, FoodTag)] = [
            ("egg", .egg), ("chicken", .poultry), ("mutton", .otherMeat), ("mutton-keema", .otherMeat),
            ("fish", .fish), ("pomfret", .fish), ("seer-fish", .fish), ("prawns", .shellfish),
        ]
        for (id, tag) in expected {
            #expect(try Self.ingredient(id, in: library).tags.contains(tag), "\(id)")
        }
    }

    @Test("only hing and saffron default to an unquantified unit")
    func unquantifiedDefaults() throws {
        let library = try Self.library()
        let unquantified = library.ingredients.filter { $0.defaultUnit.dimension == .unquantified }.map(\.id)
        #expect(Set(unquantified) == ["hing", "saffron"])
    }

    @Test("fridge ingredients have a positive shelf life; others have none")
    func fridgeShelfLife() throws {
        for ingredient in try Self.library().ingredients {
            if ingredient.defaultLocation == .fridge {
                #expect((ingredient.fridgeShelfLifeDays ?? 0) > 0, "\(ingredient.id)")
            } else {
                #expect(ingredient.fridgeShelfLifeDays == nil, "\(ingredient.id)")
            }
        }
    }
}
