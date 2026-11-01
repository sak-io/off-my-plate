import Foundation
import OMPDomain
import Testing

/// One expected parse of a golden Notes line.
struct GoldenLine: Sendable, CustomTestStringConvertible {
    let line: String
    let name: String
    var qty: Double? = nil
    var unit: MeasureUnit? = nil
    var checked = false
    var confidence: ParsedShoppingLine.Confidence = .item

    var testDescription: String { line }
}

/// Realistic lines from a Kerala household's shopping note (plan section 8 shapes, AC-11.1).
let goldenNotesLines: [GoldenLine] = [
    GoldenLine(line: "Groceries:", name: "Groceries:", confidence: .unsure),
    GoldenLine(line: "- 2 kg rice", name: "rice", qty: 2, unit: .kilogram),
    GoldenLine(line: "- rice - 2kg", name: "rice", qty: 2, unit: .kilogram),
    GoldenLine(line: "Matta rice 5kg", name: "Matta rice", qty: 5, unit: .kilogram),
    GoldenLine(line: "milk x2", name: "milk", qty: 2),
    GoldenLine(line: "2 x bread", name: "bread", qty: 2),
    GoldenLine(line: "1/2 kg onions", name: "onions", qty: 0.5, unit: .kilogram),
    GoldenLine(line: "a dozen eggs", name: "eggs", qty: 1, unit: .dozen),
    GoldenLine(line: "eggs (12)", name: "eggs", qty: 12),
    GoldenLine(line: "curry leaves", name: "curry leaves"),
    GoldenLine(line: "☐ Kappa 1 kg", name: "Kappa", qty: 1, unit: .kilogram),
    GoldenLine(line: "☑ Coconut oil 1 l", name: "Coconut oil", qty: 1, unit: .litre, checked: true),
    GoldenLine(line: "- [x] Chemmeen 500 g", name: "Chemmeen", qty: 500, unit: .gram, checked: true),
    GoldenLine(line: "- [ ] Karimeen 2", name: "Karimeen", qty: 2),
    GoldenLine(line: "✓ Kudampuli", name: "Kudampuli", checked: true),
    GoldenLine(line: "• Velichenna 500ml", name: "Velichenna", qty: 500, unit: .millilitre),
    GoldenLine(line: "* Thenga 3", name: "Thenga", qty: 3),
    GoldenLine(line: "1. Puttu podi 1kg", name: "Puttu podi", qty: 1, unit: .kilogram),
    GoldenLine(line: "2) Appam batter 1 kg", name: "Appam batter", qty: 1, unit: .kilogram),
    GoldenLine(line: "Mathi 1/2 kg", name: "Mathi", qty: 0.5, unit: .kilogram),
    GoldenLine(line: "1 1/2 kg chicken", name: "chicken", qty: 1.5, unit: .kilogram),
    GoldenLine(line: "½ kg tomatoes", name: "tomatoes", qty: 0.5, unit: .kilogram),
    GoldenLine(line: "dozen bananas", name: "bananas", qty: 1, unit: .dozen),
    GoldenLine(line: "Paneer 200 gm", name: "Paneer", qty: 200, unit: .gram),
    GoldenLine(line: "Atta - 5 kg", name: "Atta", qty: 5, unit: .kilogram),
    GoldenLine(line: "Toor dal: 1kg", name: "Toor dal", qty: 1, unit: .kilogram),
    GoldenLine(line: "Curd 1 cup", name: "Curd", qty: 1, unit: .cup),
    GoldenLine(line: "Ghee 2 tbsp", name: "Ghee", qty: 2, unit: .tablespoon),
    GoldenLine(line: "two onions", name: "onions", qty: 2),
    GoldenLine(line: "Shallots (250 g)", name: "Shallots", qty: 250, unit: .gram),
    GoldenLine(line: "Green chillies 100g", name: "Green chillies", qty: 100, unit: .gram),
    GoldenLine(line: "Coriander leaves 1 bunch", name: "Coriander leaves", qty: 1, unit: .piece),
    GoldenLine(line: "Maggi 4 packets", name: "Maggi", qty: 4, unit: .piece),
    GoldenLine(line: "Hing 1 pinch", name: "Hing"),
    GoldenLine(line: "~~Sugar 1 kg~~", name: "Sugar", qty: 1, unit: .kilogram, checked: true),
    GoldenLine(line: "call mom re sunday", name: "call mom re sunday", confidence: .unsure),
    GoldenLine(line: "https://example.com/recipe", name: "https://example.com/recipe", confidence: .unsure),
    GoldenLine(line: "Pazham (nendran) 1 kg", name: "Pazham (nendran)", qty: 1, unit: .kilogram),
    GoldenLine(line: "കറിവേപ്പില", name: "കറിവേപ്പില"),
    GoldenLine(line: "തേങ്ങ 2", name: "തേങ്ങ", qty: 2),
    GoldenLine(line: "Eggs one dozen", name: "Eggs", qty: 1, unit: .dozen),
    GoldenLine(line: "Sambar powder 100 g ✓", name: "Sambar powder", qty: 100, unit: .gram, checked: true),
    GoldenLine(line: "Bread x 2", name: "Bread", qty: 2),
    GoldenLine(line: "Oil 1.5 L", name: "Oil", qty: 1.5, unit: .litre),
]

private func expectMatches(_ parsed: ParsedShoppingLine?, _ golden: GoldenLine) {
    guard let parsed else {
        Issue.record("no parse for \(golden.line)")
        return
    }
    #expect(parsed.rawLine == golden.line)
    #expect(parsed.name == golden.name, "\(golden.line)")
    #expect(parsed.qty == golden.qty, "\(golden.line)")
    #expect(parsed.unit == golden.unit, "\(golden.line)")
    #expect(parsed.wasChecked == golden.checked, "\(golden.line)")
    #expect(parsed.confidence == golden.confidence, "\(golden.line)")
}

@Suite("ShoppingTextParser")
struct ShoppingTextParserTests {
    @Test("the golden fixture has at least 40 lines")
    func fixtureSize() {
        #expect(goldenNotesLines.count >= 40)
    }

    @Test("each golden line parses to its expected item", arguments: goldenNotesLines)
    func goldenLine(_ golden: GoldenLine) {
        let result = ShoppingTextParser.parse(golden.line)
        #expect(result.lines.count == 1)
        #expect(!result.wasTruncated)
        expectMatches(result.lines.first, golden)
    }

    @Test("the whole golden note parses line by line, skipping blank and bullet-only lines")
    func goldenNote() throws {
        var text = ""
        for (index, golden) in goldenNotesLines.enumerated() {
            text += golden.line + "\n"
            if index == 3 { text += "\n   \n-\n" }  // blank, whitespace-only and bullet-only lines
        }
        let result = ShoppingTextParser.parse(text)
        try #require(result.lines.count == goldenNotesLines.count)
        #expect(!result.wasTruncated)
        for (parsed, golden) in zip(result.lines, goldenNotesLines) { expectMatches(parsed, golden) }
        #expect(result.lines[3].lineIndex == 3)
        #expect(result.lines[4].lineIndex == 7)
    }

    @Test("R7: ticked lines are flagged and start deselected; odd lines too")
    func checkedLinesDeselected() {
        let result = ShoppingTextParser.parse("- [x] rice\n- [X] dal\n☒ salt\n✔️ oil\n- [ ] milk\ncall the plumber")
        #expect(result.lines.map(\.wasChecked) == [true, true, true, true, false, false])
        #expect(result.lines.map(\.isSelectedByDefault) == [false, false, false, false, true, false])
        #expect(result.lines.map(\.name) == ["rice", "dal", "salt", "oil", "milk", "call the plumber"])
    }

    @Test("CRLF, CR and Unicode line separators split lines; tabs and zero-width spaces are cleaned")
    func lineEndings() {
        let result = ShoppingTextParser.parse("rice\r\nmilk\rdal\u{2028}\u{FEFF}ghee\t2\u{200B} kg")
        #expect(result.lines.map(\.name) == ["rice", "milk", "dal", "ghee"])
        #expect(result.lines.map(\.rawLine) == ["rice", "milk", "dal", "\u{FEFF}ghee\t2\u{200B} kg"])
        #expect(result.lines.last?.quantity == Quantity(2, .kilogram))
    }

    @Test("a line that is only a quantity is unsure; zero or divide-by-zero amounts stay text")
    func quantityOnly() {
        let result = ShoppingTextParser.parse("2 kg\n1/2 cup\n0 kg rice\n1/0 kg dal")
        #expect(result.lines.map(\.name) == ["2 kg", "1/2 cup", "0 kg rice", "1/0 kg dal"])
        #expect(result.lines.map(\.confidence) == [.unsure, .unsure, .item, .item])
        #expect(result.lines.allSatisfy { $0.qty == nil && $0.unit == nil })
    }

    @Test("huge numbers stay text instead of overflowing")
    func hugeNumbers() {
        let result = ShoppingTextParser.parse("rice 99999999999999999999 kg\n123456 g dal")
        #expect(result.lines[0].qty == nil)
        #expect(result.lines[1].qty == 123_456)
        #expect(result.lines[1].unit == .gram)
    }

    @Test("empty input gives no lines")
    func emptyInput() {
        let result = ShoppingTextParser.parse("")
        #expect(result.lines.isEmpty)
        #expect(!result.wasTruncated)
        #expect(ShoppingTextParser.parse("\n \n\t\n- \n").lines.isEmpty)
    }

    @Test("line cap: at most 500 non-blank lines are read")
    func lineCap() {
        let exactly = String(repeating: "rice\n\n", count: 500)
        let atCap = ShoppingTextParser.parse(exactly)
        #expect(atCap.lines.count == 500)
        #expect(!atCap.wasTruncated)

        let over = ShoppingTextParser.parse(exactly + "dal\n")
        #expect(over.lines.count == ShoppingTextParser.maxLines)
        #expect(over.wasTruncated)
        #expect(over.lines.allSatisfy { $0.name == "rice" })
    }

    @Test("byte cap: at most 64 KB of UTF-8 is read, cut on a character boundary")
    func byteCap() {
        let malayalam = String(repeating: "ക", count: 30_000)  // 3 bytes each: 90 000 bytes
        let result = ShoppingTextParser.parse(malayalam)
        #expect(result.wasTruncated)
        #expect(result.lines.count == 1)
        #expect(result.lines[0].rawLine.utf8.count == 65_535)
        #expect(result.lines[0].confidence == .unsure, "an 80+ character name is not an item")

        let ascii = String(repeating: "a", count: ShoppingTextParser.maxInputBytes)
        #expect(!ShoppingTextParser.parse(ascii).wasTruncated)
        #expect(ShoppingTextParser.parse(ascii + "b").wasTruncated)
    }

    @Test("quantity and isSelectedByDefault helpers")
    func helpers() {
        let line = ParsedShoppingLine(lineIndex: 0, rawLine: "rice 2 kg", name: "rice", qty: 2, unit: .kilogram)
        #expect(line.quantity == Quantity(2, .kilogram))
        #expect(line.isSelectedByDefault)
        let count = ParsedShoppingLine(lineIndex: 0, rawLine: "milk x2", name: "milk", qty: 2)
        #expect(count.quantity == nil)
    }
}
