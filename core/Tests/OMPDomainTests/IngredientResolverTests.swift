import Foundation
import OMPDomain
import Testing

/// A slice of the seed taxonomy (same names and synonyms as `ingredients.json`), plus a
/// Malayalam-script synonym on tapioca.
enum ResolverFixture {
    static func ingredient(_ id: IngredientID, _ name: String, _ synonyms: [String]) -> Ingredient {
        Ingredient(
            id: id, name: name, synonyms: synonyms, tagStatus: .verified, aisle: .other, defaultUnit: .gram,
            defaultLocation: .shelf)
    }

    static let ingredients: [Ingredient] = [
        ingredient("onion", "Onion", ["pyaz", "pyaaz", "kanda", "vengayam", "red onion", "savala", "valiya ulli"]),
        ingredient("shallots", "Shallots", ["sambar onion", "small onion", "chinna vengayam", "kunjulli", "cheriya ulli"]),
        ingredient("tapioca", "Tapioca", ["kappa", "cassava", "maravalli kizhangu", "kolli kizhangu", "കപ്പ"]),
        ingredient("tomato", "Tomato", ["tamatar", "thakkali"]),
        ingredient("green-chilli", "Green chilli", ["hari mirch", "green chili", "pachai milagai"]),
        ingredient("curry-leaves", "Curry leaves", ["kadi patta", "kadhi patta", "kariveppilai", "karibevu", "kariveppila"]),
        ingredient("coconut", "Coconut", ["nariyal", "whole coconut", "thengai", "narial", "thenga", "nalikeram"]),
        ingredient("grated-coconut", "Grated coconut", ["fresh grated coconut", "kasa hua nariyal", "scraped coconut", "chirakiya thenga"]),
        ingredient("coconut-oil", "Coconut oil", ["nariyal tel", "thengai ennai", "khobrel", "velichenna", "velichanna"]),
        ingredient("coconut-milk", "Coconut milk", ["nariyal ka doodh", "thengai paal", "coconut cream", "thenga paal"]),
        ingredient("rice", "Rice", ["chawal", "white rice", "sona masoori", "kolam rice", "arisi", "pachari", "raw rice"]),
        ingredient("rice-flour", "Rice flour", ["chawal ka atta", "akki hittu", "arisi maavu", "idiyappam podi"]),
        ingredient("matta-rice", "Matta rice", ["rosematta rice", "kerala red rice", "palakkadan matta", "kuthari"]),
        ingredient("kala-chana", "Kala chana", ["black chickpeas", "brown chickpeas", "kadala"]),
        ingredient("chana-dal", "Chana dal", ["split bengal gram", "kadalai paruppu", "harbhara dal"]),
        ingredient("besan", "Besan", ["gram flour", "chickpea flour", "kadalai maavu", "chana atta"]),
        ingredient("lobia", "Lobia", ["black-eyed peas", "chawli", "alsande", "karamani"]),
        ingredient("red-cowpeas", "Red cowpeas", ["vanpayar", "van payar", "lal lobia", "red chawli", "karamani red"]),
        ingredient("egg", "Egg", ["anda", "ande", "eggs", "hen egg", "muttai", "mutta"]),
        ingredient("tamarind", "Tamarind", ["imli", "puli", "chinch", "hunase"]),
        ingredient("malabar-tamarind", "Malabar tamarind", ["kudampuli", "kodampuli", "fish tamarind", "gamboge"]),
        ingredient("prawns", "Prawns", ["jhinga", "jhinge", "kolambi", "chemmeen", "shrimp", "eral", "konju"]),
        ingredient("pearl-spot", "Pearl spot", ["karimeen", "green chromide"]),
        ingredient("sardine", "Sardine", ["mathi", "chaala", "mathi meen", "oil sardine", "pedvey"]),
    ]
}

private let resolver = IngredientResolver(ingredients: ResolverFixture.ingredients)

private func ids(_ query: String, limit: Int = 10) -> [IngredientID] {
    resolver.candidates(for: query, limit: limit).map(\.ingredientId)
}

@Suite("IngredientResolver")
struct IngredientResolverTests {
    @Test("exact name ranks first, case and spacing do not matter")
    func exactName() {
        let top = resolver.candidates(for: "  RICE ").first
        #expect(top?.ingredientId == "rice")
        #expect(top?.kind == .exactName)
        #expect(resolver.confidentMatch(for: "Rice")?.ingredientId == "rice")
    }

    @Test(
        "Hindi and Malayalam synonyms resolve confidently",
        arguments: [
            ("chawal", "rice"), ("pyaz", "onion"), ("kappa", "tapioca"), ("chemmeen", "prawns"),
            ("karimeen", "pearl-spot"), ("kudampuli", "malabar-tamarind"), ("velichenna", "coconut-oil"),
            ("thenga", "coconut"), ("mathi", "sardine"), ("kariveppila", "curry-leaves"), ("kuthari", "matta-rice"),
            ("കപ്പ", "tapioca"),
        ] as [(String, String)])
    func synonyms(_ query: String, _ expected: String) {
        let match = resolver.confidentMatch(for: query)
        #expect(match?.ingredientId == IngredientID(expected))
        #expect(match?.kind == .exactSynonym)
    }

    @Test("plurals match the singular: onions, tomatoes, green chillies")
    func plurals() {
        for (query, expected) in [("onions", "onion"), ("tomatoes", "tomato"), ("Green chillies", "green-chilli")] {
            let match = resolver.confidentMatch(for: query)
            #expect(match?.ingredientId == IngredientID(expected), "\(query)")
            #expect(match?.kind == .singularised, "\(query)")
        }
    }

    @Test("prefix matches for type-ahead, shorter terms first, then contains")
    func prefixThenContains() {
        #expect(ids("coco") == ["coconut", "coconut-oil", "coconut-milk", "grated-coconut"])
        let kinds = resolver.candidates(for: "coco").map(\.kind)
        #expect(kinds == [.prefix, .prefix, .prefix, .contains])
        #expect(ids("chem") == ["prawns"])
        #expect(resolver.confidentMatch(for: "chem") == nil, "a prefix is never a forced match")
    }

    @Test("an exact synonym outranks prefixes of other ingredients' synonyms")
    func exactBeforePrefix() {
        #expect(ids("kadala") == ["kala-chana", "besan", "chana-dal"])
        #expect(resolver.confidentMatch(for: "kadala")?.ingredientId == "kala-chana")
        #expect(ids("karamani") == ["lobia", "red-cowpeas"])
        #expect(ids("puli") == ["tamarind", "malabar-tamarind"])
    }

    @Test("token match: extra words in the query (fresh curry leaves)")
    func tokens() {
        let top = resolver.candidates(for: "fresh curry leaves").first
        #expect(top?.ingredientId == "curry-leaves")
        #expect(top?.kind == .token)
        #expect(resolver.confidentMatch(for: "fresh curry leaves") == nil)
    }

    @Test("one typo in a long word is a near miss")
    func nearMiss() {
        let top = resolver.candidates(for: "kariveppilla").first
        #expect(top?.ingredientId == "curry-leaves")
        #expect(top?.kind == .nearMiss)
        #expect(resolver.candidates(for: "rics").isEmpty, "near misses need 5 letters")
    }

    @Test("no match and blank queries give no candidates")
    func noMatch() {
        #expect(resolver.candidates(for: "washing powder").isEmpty)
        #expect(resolver.candidates(for: "   ").isEmpty)
        #expect(resolver.candidates(for: "rice", limit: 0).isEmpty)
        #expect(resolver.confidentMatch(for: "xyzzy") == nil)
    }

    @Test("two ingredients with the same synonym: candidates for both, no confident match")
    func ambiguous() {
        let both = IngredientResolver(ingredients: [
            ResolverFixture.ingredient("milk", "Milk", ["paal"]),
            ResolverFixture.ingredient("coconut-milk", "Coconut milk", ["paal"]),
        ])
        #expect(both.candidates(for: "paal").map(\.ingredientId) == ["coconut-milk", "milk"])
        #expect(both.confidentMatch(for: "paal") == nil)
    }

    @Test("ranking does not depend on the order of the ingredient list")
    func deterministic() {
        var rng = SplitMix64Generator(seed: 15)
        let queries = ["coco", "kadala", "rice", "puli", "onions", "fresh curry leaves", "ka", "a"]
        let expected = queries.map { resolver.candidates(for: $0, limit: 50) }
        for _ in 0..<20 {
            let shuffled = IngredientResolver(ingredients: ResolverFixture.ingredients.shuffled(using: &rng))
            #expect(queries.map { shuffled.candidates(for: $0, limit: 50) } == expected)
        }
    }

    @Test("limit caps the number of candidates")
    func limit() {
        #expect(resolver.candidates(for: "c", limit: 3).count == 3)
    }

    @Test("normalise lowercases, drops apostrophes and folds punctuation to single spaces")
    func normalise() {
        #expect(IngredientResolver.normalise("  Lady's-Finger, (fresh) ") == "ladys finger fresh")
        #expect(IngredientResolver.normalise("Black-eyed  peas") == "black eyed peas")
        #expect(IngredientResolver.normalise("കറിവേപ്പില") == "കറിവേപ്പില")
        #expect(IngredientResolver.normalise("—") == "")
    }

    @Test("MatchKind order is the documented ranking")
    func kindOrder() {
        #expect(IngredientResolver.MatchKind.allCases.sorted() == IngredientResolver.MatchKind.allCases)
        #expect(IngredientResolver.MatchKind.exactName < .nearMiss)
    }
}

/// SplitMix64: fixed-seed generator so shuffles and fuzz inputs are reproducible.
struct SplitMix64Generator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
