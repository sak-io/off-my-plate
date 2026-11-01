import Foundation
import OMPDomain
import OMPRecipes
import Testing

/// `IngredientResolver` over the real bundled taxonomy (AC-9.1 picker search, AC-11.1 Notes rows).
@Suite("Resolver over the bundled seed")
struct SeedResolverTests {
    @Test("every name, and every synonym no other ingredient shares, resolves confidently to its ingredient")
    func everyUniqueTermResolves() throws {
        let ingredients = try SeedLoader.loadBundled().ingredients
        let resolver = IngredientResolver(ingredients: ingredients)
        var owners: [String: Set<IngredientID>] = [:]
        for ingredient in ingredients {
            for term in [ingredient.name] + ingredient.synonyms {
                owners[IngredientResolver.normalise(term), default: []].insert(ingredient.id)
            }
        }
        for ingredient in ingredients {
            #expect(resolver.confidentMatch(for: ingredient.name)?.ingredientId == ingredient.id, "\(ingredient.name)")
            for synonym in ingredient.synonyms where owners[IngredientResolver.normalise(synonym)]?.count == 1 {
                #expect(resolver.confidentMatch(for: synonym)?.ingredientId == ingredient.id, "\(synonym)")
            }
        }
    }

    @Test("Kerala and Hindi shopping words from a Notes list map to the right ingredients")
    func keralaNote() throws {
        let resolver = IngredientResolver(ingredients: try SeedLoader.loadBundled().ingredients)
        let note = """
            - 2 kg kappa
            Chemmeen 500 g
            Karimeen 2
            Kudampuli
            Velichenna 1 l
            Thenga 3
            Mathi 1/2 kg
            kariveppila
            chawal 5kg
            onions 1 kg
            """
        let expected: [IngredientID?] = [
            "tapioca", "prawns", "pearl-spot", "malabar-tamarind", "coconut-oil", "coconut", "sardine", "curry-leaves",
            "rice", "onion",
        ]
        let lines = ShoppingTextParser.parse(note).lines
        #expect(lines.map { resolver.confidentMatch(for: $0.name)?.ingredientId } == expected)
    }
}
