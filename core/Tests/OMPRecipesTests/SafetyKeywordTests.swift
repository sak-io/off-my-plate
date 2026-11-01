import Foundation
import OMPDomain
import OMPRecipes
import Testing

/// The safety text parser fed with the bundled catalog keywords, the way the app wires it
/// (AC-2.3, AC-2.4, plan R4).
@Suite("Safety keywords (bundled catalog)")
struct SafetyKeywordTests {
    static func parser() throws -> (SafetyTextParser, SeedCatalog) {
        let catalog = try SeedLoader.loadBundled().catalog
        return (SafetyTextParser(keywords: catalog.restrictionKeywords), catalog)
    }

    static func ids(_ candidates: [SafetyCandidate]) -> [RestrictionID] {
        candidates.compactMap { candidate in
            if case .restriction(let id, _, _) = candidate { return id }
            return nil
        }
    }

    @Test("every catalog keyword on its own selects exactly its restrictions, nothing unmapped")
    func everyKeyword() throws {
        let (parser, catalog) = try Self.parser()
        for (keyword, expected) in catalog.restrictionKeywords {
            let candidates = parser.parse(keyword)
            #expect(Set(Self.ids(candidates)) == Set(expected), "\(keyword)")
            #expect(!candidates.contains { $0.isUnmapped }, "\(keyword)")
        }
    }

    @Test("no catalog keyword is a word the parser ignores or splits on")
    func keywordsAreNeverIgnored() throws {
        let (_, catalog) = try Self.parser()
        for keyword in catalog.restrictionKeywords.keys {
            let key = IngredientResolver.normalise(keyword)
            #expect(!SafetyTextParser.ignoredWords.contains(key), "\(keyword)")
            #expect(!SafetyTextParser.clauseBreakWords.contains(key), "\(keyword)")
        }
    }

    @Test("the spec examples: 'nuts', 'no beef', 'can't have dairy'")
    func specExamples() throws {
        let (parser, _) = try Self.parser()
        #expect(Self.ids(parser.parse("one of us can't have nuts")) == ["peanuts", "tree-nuts"])
        #expect(Self.ids(parser.parse("no beef")) == ["beef"])
        #expect(Self.ids(parser.parse("can't have dairy")) == ["milk"])
        #expect(parser.parse("kiwi") == [.unmapped(text: "kiwi", memberHint: nil)])
    }

    /// Malayalam words added in T16, pending owner sign-off (seed review sheet).
    @Test(
        "Malayalam keywords select their restrictions",
        arguments: [
            ("meen", "fish"), ("mutta", "egg"), ("kappalandi", "peanuts"), ("nilakkadala", "peanuts"),
            ("paal", "milk"), ("chemmeen", "shellfish"), ("konju", "shellfish"), ("njandu", "shellfish"),
            ("ellu", "sesame"), ("kaduku", "mustard"), ("gothambu", "wheat-gluten"), ("andiparippu", "tree-nuts"),
        ] as [(String, String)])
    func malayalam(_ keyword: String, _ restriction: String) throws {
        let (parser, catalog) = try Self.parser()
        #expect(catalog.restrictions(forKeyword: keyword).map(\.id) == [RestrictionID(restriction)])
        #expect(Self.ids(parser.parse("no \(keyword)")) == [RestrictionID(restriction)])
    }
}
