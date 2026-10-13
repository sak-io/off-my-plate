import Foundation
import OMPDomain
import Testing

/// The catalog keyword table (same entries as `catalog.json`, including the Hindi and Malayalam
/// words), passed in the way the app passes `SeedCatalog.restrictionKeywords`.
enum SafetyFixture {
    static let keywords: [String: [RestrictionID]] = [
        "almond": ["tree-nuts"],
        "anda": ["egg"],
        "ande": ["egg"],
        "andiparippu": ["tree-nuts"],
        "atta": ["wheat-gluten"],
        "badam": ["tree-nuts"],
        "beef": ["beef"],
        "cashew": ["tree-nuts"],
        "chemmeen": ["shellfish"],
        "crab": ["shellfish"],
        "dairy": ["milk"],
        "doodh": ["milk"],
        "dudh": ["milk"],
        "egg": ["egg"],
        "eggs": ["egg"],
        "ellu": ["sesame"],
        "fish": ["fish"],
        "gehu": ["wheat-gluten"],
        "gehun": ["wheat-gluten"],
        "gluten": ["wheat-gluten"],
        "gothambu": ["wheat-gluten"],
        "groundnut": ["peanuts"],
        "groundnuts": ["peanuts"],
        "jain": ["jain"],
        "kaduku": ["mustard"],
        "kaju": ["tree-nuts"],
        "kappalandi": ["peanuts"],
        "konju": ["shellfish"],
        "lactose": ["milk"],
        "machhi": ["fish"],
        "machhli": ["fish"],
        "machli": ["fish"],
        "maida": ["wheat-gluten"],
        "meen": ["fish"],
        "milk": ["milk"],
        "moongphali": ["peanuts"],
        "mustard": ["mustard"],
        "mutta": ["egg"],
        "nilakkadala": ["peanuts"],
        "njandu": ["shellfish"],
        "no meat": ["vegetarian"],
        "nut": ["peanuts", "tree-nuts"],
        "nuts": ["peanuts", "tree-nuts"],
        "paal": ["milk"],
        "peanut": ["peanuts"],
        "peanuts": ["peanuts"],
        "pistachio": ["tree-nuts"],
        "pork": ["pork"],
        "prawn": ["shellfish"],
        "prawns": ["shellfish"],
        "rai": ["mustard"],
        "sarson": ["mustard"],
        "sesame": ["sesame"],
        "shellfish": ["shellfish"],
        "shrimp": ["shellfish"],
        "soy": ["soy"],
        "soya": ["soy"],
        "til": ["sesame"],
        "tree nut": ["tree-nuts"],
        "tree nuts": ["tree-nuts"],
        "veg": ["vegetarian"],
        "vegetarian": ["vegetarian"],
        "walnut": ["tree-nuts"],
        "wheat": ["wheat-gluten"],
    ]
    static let parser = SafetyTextParser(keywords: SafetyFixture.keywords)

    /// "peanuts", "peanuts @Meera", "?kiwi", "?kiwi @Meera".
    static func describe(_ candidates: [SafetyCandidate]) -> [String] {
        candidates.map { candidate in
            let hint = candidate.memberHint.map { " @" + $0 } ?? ""
            switch candidate {
            case .restriction(let id, _, _): return id.rawValue + hint
            case .unmapped(let text, _): return "?" + text + hint
            }
        }
    }

    /// Every word the parser may skip without reporting it: grammar words, clause breaks and
    /// the words of keywords (a keyword word is always covered by a restriction row).
    static let coveredElsewhere: Set<String> = {
        var words = SafetyTextParser.ignoredWords.union(SafetyTextParser.clauseBreakWords)
        for keyword in SafetyFixture.keywords.keys {
            for word in IngredientResolver.normalise(keyword).split(separator: " ") {
                words.insert(String(word))
            }
        }
        return words
    }()

    /// The input words that appear in no candidate (restriction text, unmapped text or hint).
    static func droppedWords(_ text: String, _ candidates: [SafetyCandidate]) -> [String] {
        var reported = Set<String>()
        for candidate in candidates {
            var texts: [String] = []
            switch candidate {
            case .restriction(_, let matched, let hint): texts = [matched, hint ?? ""]
            case .unmapped(let unmapped, let hint): texts = [unmapped, hint ?? ""]
            }
            for text in texts {
                for word in IngredientResolver.normalise(text).split(separator: " ") { reported.insert(String(word)) }
            }
        }
        var dropped: [String] = []
        for word in IngredientResolver.normalise(text).split(separator: " ").map(String.init) {
            if coveredElsewhere.contains(word) || reported.contains(word) { continue }
            // "Meera's" is reported as "Meera"; "nuts's" as "nuts".
            if word.hasSuffix("s") {
                let stem = String(word.dropLast())
                if reported.contains(stem) || coveredElsewhere.contains(stem) { continue }
            }
            dropped.append(word)
        }
        return dropped
    }
}

/// Typed and spoken answers to the safety question (AC-2.3, AC-2.4).
let safetyGoldenAnswers: [(String, [String])] = [
        ("nuts", ["peanuts", "tree-nuts"]),
        ("no beef", ["beef"]),
        ("can't have dairy", ["milk"]),
        ("Meera has a nut allergy", ["peanuts @Meera", "tree-nuts @Meera"]),
        ("one of us can't have nuts", ["peanuts", "tree-nuts"]),
        ("no beef, one of us can't have nuts", ["beef", "peanuts", "tree-nuts"]),
        ("kiwi", ["?kiwi"]),
        ("no beef and kiwi", ["beef", "?kiwi"]),
        ("Meera has a kiwi allergy", ["?Meera", "?kiwi"]),
        ("Meera's nut allergy", ["peanuts @Meera", "tree-nuts @Meera"]),
        ("Ravi: shellfish", ["shellfish @Ravi"]),
        ("no peanuts for Meera", ["peanuts @Meera"]),
        ("allergic to almonds", ["tree-nuts"]),
        ("tree nut allergy", ["tree-nuts"]),
        ("Tree-nuts", ["tree-nuts"]),
        ("no meat", ["vegetarian"]),
        ("gluten free", ["wheat-gluten"]),
        ("lactose intolerant", ["milk"]),
        ("mutta", ["egg"]),
        ("meen", ["fish"]),
        ("kappalandi", ["peanuts"]),
        ("paal", ["milk"]),
        ("anda nahi", ["egg"]),
        ("No eggs, no fish; prawns.", ["egg", "fish", "shellfish"]),
        ("PEANUTS!!", ["peanuts"]),
        ("", []),
        ("   ", []),
        ("allergy", ["?allergy"]),
        ("nothing", ["?nothing"]),
        ("Meera", ["?Meera"]),
        ("no beef 🙂", ["beef"]),
        ("nuts nuts", ["peanuts", "tree-nuts"]),
        ("Meera can't have nuts and Ravi can't have nuts", ["peanuts @Meera", "tree-nuts @Meera", "peanuts @Ravi", "tree-nuts @Ravi"]),
        ("Meera can't have nuts or kiwi", ["peanuts @Meera", "tree-nuts @Meera", "?kiwi"]),
        ("Meera can't have nuts kiwi", ["peanuts @Meera", "tree-nuts @Meera", "?kiwi @Meera"]),
        ("kiwi is a problem", ["?kiwi"]),
        ("my son is allergic to cashews", ["tree-nuts @my son"]),
        ("no pork or beef", ["pork", "beef"]),
        ("we are vegetarian", ["vegetarian"]),
        ("Jain", ["jain"]),
        ("no meat", ["vegetarian"]),
        ("I don't eat meat", ["?meat"]),
        ("no paneer", ["?paneer"]),
        ("strictly no groundnuts", ["peanuts"]),
        ("mustard and sesame", ["mustard", "sesame"]),
        ("can't have soya", ["soy"]),
        ("no wheat/maida", ["wheat-gluten"]),
        ("Meera's", ["?Meera"]),
        ("'s", ["?s"]),
        ("മുട്ട", ["?മുട്ട"]),
]

@Suite("SafetyTextParser")
struct SafetyTextParserTests {
    let parser = SafetyFixture.parser

    @Test("golden answers map to the expected candidates", arguments: safetyGoldenAnswers)
    func golden(_ text: String, _ expected: [String]) {
        #expect(SafetyFixture.describe(parser.parse(text)) == expected)
    }

    @Test("'nuts' selects peanuts and tree nuts, each its own row, with the words that matched")
    func nuts() {
        #expect(
            parser.parse("one of us can't have nuts") == [
                .restriction("peanuts", matchedText: "nuts", memberHint: nil),
                .restriction("tree-nuts", matchedText: "nuts", memberHint: nil),
            ])
    }

    @Test("a member name is only a hint, never a restriction or an unmapped row")
    func memberHintOnly() {
        let candidates = parser.parse("Meera has a nut allergy")
        #expect(candidates.allSatisfy { $0.memberHint == "Meera" })
        #expect(!candidates.contains { $0.isUnmapped })
        #expect(candidates.count == 2)
    }

    @Test("AC-2.4: unknown text is returned as unmapped, never dropped and never 'no restriction'")
    func unknownIsUnmapped() {
        #expect(parser.parse("kiwi") == [.unmapped(text: "kiwi", memberHint: nil)])
        #expect(parser.parse("no beef and kiwi").contains(.unmapped(text: "kiwi", memberHint: nil)))
        #expect(parser.parse("nothing") == [.unmapped(text: "nothing", memberHint: nil)])
        #expect(parser.parse("I don't eat meat") == [.unmapped(text: "meat", memberHint: nil)])
    }

    @Test("with an empty keyword table everything comes back unmapped")
    func emptyTable() {
        let empty = SafetyTextParser(keywords: [:])
        #expect(empty.parse("no nuts, beef") == [
            .unmapped(text: "nuts", memberHint: nil), .unmapped(text: "beef", memberHint: nil),
        ])
    }

    @Test("keywords are matched case-insensitively and merged when two spellings normalise the same")
    func keywordNormalisation() {
        let parser = SafetyTextParser(keywords: ["Tree Nuts": ["tree-nuts"], "tree-nuts": ["tree-nuts", "peanuts"]])
        #expect(SafetyFixture.describe(parser.parse("TREE NUTS")) == ["tree-nuts", "peanuts"])
    }

    @Test("text over the cap comes back as one unmapped row, not dropped")
    func overflow() {
        let long = String(repeating: "no beef ", count: 300) + "kiwi"
        let candidates = parser.parse(long)
        #expect(candidates.first == .restriction("beef", matchedText: "beef", memberHint: nil))
        guard case .unmapped(let text, .none)? = candidates.last else {
            Issue.record("expected the overflow as an unmapped row")
            return
        }
        #expect(text.hasSuffix("\u{2026}"))
        #expect(candidates.count == 2)
    }

    @Test("AC-2.4: no golden answer drops a word it did not understand")
    func goldenNeverDrops() {
        for (text, _) in safetyGoldenAnswers {
            #expect(SafetyFixture.droppedWords(text, parser.parse(text)).isEmpty, "\(text)")
        }
    }

    @Test("no ignored word is a catalog keyword")
    func ignoredWordsAreNotKeywords() {
        for keyword in SafetyFixture.keywords.keys {
            #expect(!SafetyTextParser.ignoredWords.contains(IngredientResolver.normalise(keyword)), "\(keyword)")
        }
    }
}
