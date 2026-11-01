import Foundation
import OMPDomain
import Testing

/// Seeded fuzzing of the Notes parser and the resolver with random Unicode and lengths
/// (plan section 11: untrusted Share Extension input). Failures print the seed and iteration.
@Suite("Parser fuzz")
struct ParserFuzzTests {
    /// Pieces that steer random text toward the parser's interesting paths.
    static let fragments: [String] = [
        "2 kg ", "rice", " - ", "2kg", "x2", " x ", "1/2", "1/0", "½", "1½", "(", ")", "(12)", "- [x] ", "- [ ] ", "[",
        "☐", "☑", "✓", "✔️", "~~", "• ", "1. ", "12) ", "dozen", "a ", "half ", "pinch", "\n", "\r\n", "\r",
        "\u{2028}", "\t", " ", "\u{200D}", "\u{200B}", "\u{FEFF}", "\u{0301}", "\u{0D4D}", "കറിവേപ്പില", "തേങ്ങ",
        "प्याज़", "👨‍👩‍👧", "🇮🇳", "999999999", "0", ".", "..", "https://", ":", "?", "\u{0}", "\u{7F}",
    ]

    static func randomScalar(_ rng: inout SplitMix64Generator) -> Unicode.Scalar {
        let ranges: [ClosedRange<UInt32>] = [
            0x20...0x7E, 0x00...0x1F, 0x0D00...0x0D7F, 0x0900...0x097F, 0x0300...0x036F, 0x2000...0x206F,
            0x1F300...0x1FAFF, 0x0...0x10FFFF,
        ]
        let range = ranges[Int(rng.next() % UInt64(ranges.count))]
        let span = UInt64(range.upperBound - range.lowerBound) + 1
        let value = range.lowerBound + UInt32(rng.next() % span)
        return Unicode.Scalar(value) ?? "?"  // surrogate code points are not scalars
    }

    static func randomText(_ rng: inout SplitMix64Generator, maxPieces: Int) -> String {
        let pieces = Int(rng.next() % UInt64(maxPieces + 1))
        var text = ""
        for _ in 0..<pieces {
            if rng.next() % 2 == 0 {
                text += fragments[Int(rng.next() % UInt64(fragments.count))]
            } else {
                text.unicodeScalars.append(randomScalar(&rng))
            }
        }
        return text
    }

    static func checkInvariants(_ text: String, _ context: String) {
        let result = ShoppingTextParser.parse(text)
        #expect(result.lines.count <= ShoppingTextParser.maxLines, "\(context)")
        let bytes = result.lines.reduce(0) { $0 + $1.rawLine.utf8.count }
        #expect(bytes <= ShoppingTextParser.maxInputBytes, "\(context)")
        if text.utf8.count <= ShoppingTextParser.maxInputBytes, result.lines.count < ShoppingTextParser.maxLines {
            #expect(!result.wasTruncated, "\(context)")
        }
        var previousIndex = -1
        for line in result.lines {
            #expect(!line.name.isEmpty, "\(context)")
            #expect(line.lineIndex > previousIndex, "\(context)")
            previousIndex = line.lineIndex
            if let qty = line.qty {
                #expect(qty.isFinite && qty > 0, "\(context)")
            }
            if let unit = line.unit {
                #expect(line.qty != nil && unit.isQuantified, "\(context)")
            }
        }
        #expect(ShoppingTextParser.parse(text) == result, "deterministic: \(context)")
    }

    @Test("random short and medium texts never crash and keep every invariant", arguments: [1, 2, 3, 4])
    func randomTexts(seed: UInt64) {
        var rng = SplitMix64Generator(seed: seed)
        for iteration in 0..<150 {
            let text = Self.randomText(&rng, maxPieces: 400)
            Self.checkInvariants(text, "seed \(seed) iteration \(iteration)")
        }
    }

    @Test("random texts over the caps are cut to 64 KB and 500 lines")
    func overCaps() {
        var rng = SplitMix64Generator(seed: 64)
        for iteration in 0..<4 {
            var text = ""
            while text.utf8.count < 100_000 { text += Self.randomText(&rng, maxPieces: 200) + "\n" }
            Self.checkInvariants(text, "over caps iteration \(iteration)")
            #expect(ShoppingTextParser.parse(text).wasTruncated)
        }
        let manyLines = String(repeating: "x\n", count: 5_000)
        let result = ShoppingTextParser.parse(manyLines)
        #expect(result.lines.count == 500)
        #expect(result.wasTruncated)
    }

    @Test("the resolver never crashes on random queries and respects its limit")
    func resolverFuzz() {
        let resolver = IngredientResolver(ingredients: ResolverFixture.ingredients)
        var rng = SplitMix64Generator(seed: 2026)
        for iteration in 0..<500 {
            let query = Self.randomText(&rng, maxPieces: 40)
            let limit = Int(rng.next() % 6)
            let candidates = resolver.candidates(for: query, limit: limit)
            #expect(candidates.count <= limit, "iteration \(iteration)")
            #expect(resolver.candidates(for: query, limit: limit) == candidates, "iteration \(iteration)")
            if let match = resolver.confidentMatch(for: query) {
                #expect(match.kind <= .singularised, "iteration \(iteration)")
            }
        }
        let long = String(repeating: "kappa ", count: 20_000)
        #expect(resolver.candidates(for: long).count <= 10)
    }
}
