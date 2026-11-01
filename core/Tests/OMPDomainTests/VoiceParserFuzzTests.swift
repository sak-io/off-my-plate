import Foundation
import OMPDomain
import Testing

/// Seeded fuzzing of the voice grammar and the safety text parser (plan section 11: transcripts
/// and typed answers are untrusted). Failures print the seed and iteration.
@Suite("Voice parser fuzz")
struct VoiceParserFuzzTests {
    /// Grammar words that steer random text toward the parsers' interesting paths.
    static let spokenFragments: [String] = [
        "I bought ", "add ", "we're out of ", "used up ", "remove ", "approve", "approve the plan", "looks good",
        " and ", ", ", ". ", "2 ", "kg ", "rice", "a ", "dozen ", "half ", "one ", "twenty ", "hundred ",
        "and a half ", "of ", "the ", "1/2", "½", "eggs", "0 ", "999999 ", "1.", "pinch ", "kappa", "nuts",
        "Meera", "'s", ":", "can't have ", "allergy", "for ", "tree-nuts", "mutta", "paal", "kiwi",
    ]

    static func randomText(_ rng: inout SplitMix64Generator, maxPieces: Int) -> String {
        let pieces = Int(rng.next() % UInt64(maxPieces + 1))
        var text = ""
        for _ in 0..<pieces {
            if rng.next() % 3 == 0 {
                text += ParserFuzzTests.randomText(&rng, maxPieces: 2)
            } else {
                text += spokenFragments[Int(rng.next() % UInt64(spokenFragments.count))]
            }
        }
        return text
    }

    static func checkSpoken(_ text: String, _ context: String) {
        let parser = SpokenFixture.parser
        let result = parser.parse(text)
        #expect(result.commands.filter { $0 == .openApprovalSheet }.count <= 1, "\(context)")
        for command in result.commands {
            switch command {
            case .add(let items), .markOut(let items), .remove(let items):
                #expect(!items.isEmpty, "\(context)")
            case .openApprovalSheet:
                break
            }
        }
        for item in result.pantryItems {
            #expect(!item.name.isEmpty, "\(context)")
            if let qty = item.qty {
                #expect(qty.isFinite && qty > 0, "\(context)")
            }
            if let unit = item.unit {
                #expect(item.qty != nil && unit.isQuantified, "\(context)")
            }
        }
        for piece in result.unparsed {
            #expect(!piece.isEmpty, "\(context)")
        }
        #expect(parser.parse(text) == result, "deterministic: \(context)")
    }

    static func checkSafety(_ text: String, _ context: String) {
        let parser = SafetyFixture.parser
        let candidates = parser.parse(text)
        #expect(Set(candidates).count == candidates.count, "no duplicate rows: \(context)")
        for candidate in candidates {
            switch candidate {
            case .restriction(let id, let matched, _):
                #expect(SafetyFixture.keywords.values.contains { $0.contains(id) }, "\(context)")
                #expect(!matched.isEmpty, "\(context)")
            case .unmapped(let unmapped, _):
                #expect(!unmapped.isEmpty, "\(context)")
            }
        }
        if text.count <= SafetyTextParser.maxInputLength {
            #expect(SafetyFixture.droppedWords(text, candidates).isEmpty, "never drops a word: \(context)")
        }
        #expect(parser.parse(text) == candidates, "deterministic: \(context)")
    }

    @Test("random transcripts never crash and keep every invariant", arguments: [11, 12, 13, 14])
    func spoken(seed: UInt64) {
        var rng = SplitMix64Generator(seed: seed)
        for iteration in 0..<200 {
            Self.checkSpoken(Self.randomText(&rng, maxPieces: 40), "seed \(seed) iteration \(iteration)")
        }
    }

    @Test("random safety answers never crash, never drop an unknown word", arguments: [21, 22, 23, 24])
    func safety(seed: UInt64) {
        var rng = SplitMix64Generator(seed: seed)
        for iteration in 0..<200 {
            Self.checkSafety(Self.randomText(&rng, maxPieces: 30), "seed \(seed) iteration \(iteration)")
        }
    }

    @Test("long inputs are capped without crashing")
    func longInputs() {
        var rng = SplitMix64Generator(seed: 99)
        var text = ""
        while text.count < 20_000 { text += Self.randomText(&rng, maxPieces: 50) }
        #expect(SpokenFixture.parser.parse(text).wasTruncated)
        let candidates = SafetyFixture.parser.parse(text)
        #expect(candidates.last?.isUnmapped == true)
        Self.checkSpoken(String(repeating: "add ", count: 10_000), "repeated verb")
        Self.checkSafety(String(repeating: "and ", count: 400), "repeated clause break")
    }
}
