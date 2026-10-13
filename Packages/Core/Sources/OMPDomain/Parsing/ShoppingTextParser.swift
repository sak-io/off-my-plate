import Foundation

/// One line of a shared note, as understood by `ShoppingTextParser` (plan section 8, AC-11.1).
public struct ParsedShoppingLine: Sendable, Hashable {
    /// How sure the parser is that the line is a shopping item.
    public enum Confidence: String, Sendable, Hashable {
        /// Looks like an item ("2 kg rice", "curry leaves").
        case item
        /// Odd line ("call mom re sunday", "Groceries:", a link): shown under "Not sure about
        /// these" (S-40) and removed unless the user keeps it.
        case unsure
    }

    /// 0-based position of the line in the (capped) input, counting blank lines.
    public let lineIndex: Int
    /// The line exactly as shared.
    public let rawLine: String
    /// The item name with bullets, checkboxes and the quantity removed, in the note's casing.
    public let name: String
    /// The amount, if the line had one. With no `unit` it is a count of the item ("milk x2").
    public let qty: Double?
    public let unit: MeasureUnit?
    /// True when the line was ticked in the note ("- [x]", "✓", "☑", "~~text~~"). Per plan R7 such
    /// lines start deselected on the review screen.
    public let wasChecked: Bool
    public let confidence: Confidence

    public init(
        lineIndex: Int, rawLine: String, name: String, qty: Double? = nil, unit: MeasureUnit? = nil,
        wasChecked: Bool = false, confidence: Confidence = .item
    ) {
        self.lineIndex = lineIndex
        self.rawLine = rawLine
        self.name = name
        self.qty = qty
        self.unit = unit
        self.wasChecked = wasChecked
        self.confidence = confidence
    }

    /// The amount as a `Quantity` when both amount and unit are known.
    public var quantity: Quantity? {
        guard let qty, let unit else { return nil }
        return Quantity(qty, unit)
    }

    /// Whether the review screen pre-selects the line: not ticked in the note and not odd.
    public var isSelectedByDefault: Bool { !wasChecked && confidence == .item }
}

/// The parsed lines of one shared note.
public struct ShoppingTextParseResult: Sendable, Hashable {
    /// Non-blank lines in note order; never more than `ShoppingTextParser.maxLines`.
    public let lines: [ParsedShoppingLine]
    /// True when the input went over the byte or line cap and the rest was ignored.
    public let wasTruncated: Bool

    public init(lines: [ParsedShoppingLine], wasTruncated: Bool) {
        self.lines = lines
        self.wasTruncated = wasTruncated
    }
}

/// Rule-based parser for shopping lists shared from Apple Notes (plan section 8, AC-11.1).
///
/// The input is untrusted text (plan section 11): at most `maxInputBytes` of UTF-8 and
/// `maxLines` non-blank lines are read; the rest is ignored and reported. Text only: links are
/// never followed, they are just "unsure" lines (AC-11.4).
///
/// Supported shapes: `2 kg rice`, `rice - 2kg`, `rice 2kg`, `milk x2`, `2 x milk`, `1/2 kg onions`,
/// `1 1/2 kg`, `½ kg`, `a dozen eggs`, `dozen eggs`, `eggs (12)`, `two onions`, `2 kg of rice`, and a
/// bare name (`curry leaves`). Bullets and checkboxes are stripped: `-`, `*`, `+`, `•`, `◦`, `☐`,
/// `☑`, `✓`, `✔`, `✅`, `- [ ]`, `- [x]`, `1.`, `1)`.
public enum ShoppingTextParser {
    /// 64 KB of UTF-8 (plan section 11).
    public static let maxInputBytes = 64 * 1024
    /// Non-blank lines read (plan section 11).
    public static let maxLines = 500
    /// A name longer than this (in characters) is "unsure".
    static let maxItemNameLength = 80
    /// A name with more words than this and no quantity is "unsure" (a sentence, not an item).
    static let maxItemWordsWithoutQuantity = 5
    /// Words that mark a to-do or note rather than an item ("call mom re sunday").
    static let nonItemCueWords: Set<String> = [
        "call", "ring", "phone", "pay", "email", "send", "book", "meeting", "appointment", "remind", "remember",
        "todo", "tomorrow", "today", "re",
    ]

    public static func parse(_ text: String) -> ShoppingTextParseResult {
        let (capped, overByteCap) = cappedPrefix(of: text)
        var lines: [ParsedShoppingLine] = []
        var overLineCap = false
        var lineIndex = 0
        for raw in capped.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            defer { lineIndex += 1 }
            guard let parsed = parseLine(raw, index: lineIndex) else { continue }
            if lines.count == maxLines {
                overLineCap = true
                break
            }
            lines.append(parsed)
        }
        return ShoppingTextParseResult(lines: lines, wasTruncated: overByteCap || overLineCap)
    }

    /// The longest prefix of whole characters within `maxInputBytes`, and whether text was cut.
    static func cappedPrefix(of text: String) -> (Substring, Bool) {
        if text.utf8.count <= maxInputBytes { return (text[...], false) }
        var bytes = 0
        var end = text.startIndex
        for index in text.indices {
            let width = String(text[index]).utf8.count
            if bytes + width > maxInputBytes { break }
            bytes += width
            end = text.index(after: index)
        }
        return (text[..<end], true)
    }

    /// Parses one line; nil for a blank line or one that is only a bullet.
    static func parseLine(_ raw: Substring, index: Int) -> ParsedShoppingLine? {
        var body = Substring(cleaned(raw))
        var wasChecked = false
        stripMarkers(&body, wasChecked: &wasChecked)
        if body.count >= 4, body.hasPrefix("~~"), body.hasSuffix("~~") {
            wasChecked = true
            body = trimmed(body.dropFirst(2).dropLast(2))
        }
        guard !body.isEmpty else { return nil }

        let words = body.split(whereSeparator: { $0.isWhitespace }).map(QuantityToken.init)
        let parsed = leadingQuantity(words) ?? trailingQuantity(body, words)
        let name: String
        var qty: Double?
        var unit: MeasureUnit?
        var onlyQuantityWords = false
        if let parsed, !parsed.name.isEmpty {
            name = parsed.name
            qty = parsed.amount
            unit = parsed.unit
        } else {
            name = words.map { String($0.text) }.joined(separator: " ")
            onlyQuantityWords = !words.contains { $0.kind == .word }
        }
        if let current = unit, !current.isQuantified {
            unit = nil
            qty = nil
        }
        let confidence: ParsedShoppingLine.Confidence =
            onlyQuantityWords ? .unsure : classify(name: name, hasQuantity: qty != nil)
        return ParsedShoppingLine(
            lineIndex: index, rawLine: String(raw), name: name, qty: qty, unit: unit, wasChecked: wasChecked,
            confidence: confidence)
    }

    // MARK: - Cleaning and markers

    /// Tabs become spaces; other control characters, zero-width spaces and byte-order marks go.
    /// Zero-width joiners stay: Malayalam and Devanagari spellings need them.
    private static func cleaned(_ raw: Substring) -> String {
        var result = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            if scalar == "\t" {
                result.append(" ")
            } else if scalar.properties.generalCategory == .control || scalar.value == 0xFEFF
                || scalar.value == 0x200B || scalar.value == 0x2060
            {
                continue
            } else {
                result.append(scalar)
            }
        }
        return String(result)
    }

    private static func trimmed(_ text: Substring) -> Substring {
        guard let first = text.firstIndex(where: { !$0.isWhitespace }),
            let last = text.lastIndex(where: { !$0.isWhitespace })
        else { return text[text.endIndex...] }
        return text[first...last]
    }

    /// First Unicode scalar values that mark a ticked checklist item.
    private static let checkedMarks: Set<UInt32> = [0x2611, 0x2612, 0x2713, 0x2714, 0x2705, 0x1F5F9]
    /// Bullets and empty boxes that may be followed directly by text.
    private static let symbolBullets: Set<UInt32> = [
        0x2022, 0x25E6, 0x25AA, 0x25AB, 0x2023, 0x2043, 0x00B7, 0x25CF, 0x25CB, 0x25A0, 0x25A1, 0x2610, 0x27A4,
        0x2192, 0x2013, 0x2014,
    ]
    /// ASCII bullets: only when followed by a space or a checkbox, so "-2" is not touched.
    private static let asciiBullets: Set<Character> = ["-", "*", "+", ">"]

    private static func firstScalar(_ character: Character) -> UInt32 {
        character.unicodeScalars.first?.value ?? 0
    }

    /// Strips leading bullets, numbering and checkboxes, and trailing ticks.
    private static func stripMarkers(_ body: inout Substring, wasChecked: inout Bool) {
        body = trimmed(body)
        var changed = true
        var rounds = 0
        while changed, rounds < 8, let first = body.first {
            changed = false
            rounds += 1
            if let box = checkbox(body) {
                wasChecked = wasChecked || box.checked
                body = trimmed(body.dropFirst(box.length))
                changed = true
            } else if checkedMarks.contains(firstScalar(first)) {
                wasChecked = true
                body = trimmed(body.dropFirst())
                changed = true
            } else if symbolBullets.contains(firstScalar(first)) {
                body = trimmed(body.dropFirst())
                changed = true
            } else if asciiBullets.contains(first) {
                let next = body.dropFirst().first
                if next == nil || next!.isWhitespace || next == "[" {
                    body = trimmed(body.dropFirst())
                    changed = true
                }
            } else if let numbering = numberingLength(body) {
                body = trimmed(body.dropFirst(numbering))
                changed = true
            }
        }
        while let last = body.last, checkedMarks.contains(firstScalar(last)) {
            wasChecked = true
            body = trimmed(body.dropLast())
        }
    }

    /// "[ ]", "[x]", "[X]", "[✓]" at the start: its length and whether it is ticked.
    private static func checkbox(_ body: Substring) -> (length: Int, checked: Bool)? {
        let head = Array(body.prefix(3))
        guard head.count == 3, head[0] == "[", head[2] == "]" else { return nil }
        let mark = head[1]
        if mark == " " { return (3, false) }
        if mark == "x" || mark == "X" || checkedMarks.contains(firstScalar(mark)) { return (3, true) }
        return nil
    }

    /// "1." or "12)" followed by a space: a numbered list marker, not a quantity.
    private static func numberingLength(_ body: Substring) -> Int? {
        var length = 0
        for character in body {
            guard let ascii = character.asciiValue, ascii >= 48, ascii <= 57, length < 3 else { break }
            length += 1
        }
        guard length > 0 else { return nil }
        let rest = body.dropFirst(length)
        guard let marker = rest.first, marker == "." || marker == ")",
            let after = rest.dropFirst().first, after.isWhitespace
        else { return nil }
        return length + 1
    }

    // MARK: - Quantity shapes

    private struct Extracted {
        var name: String
        var amount: Double
        var unit: MeasureUnit?
    }

    /// Separators between a name and a trailing quantity ("rice - 2kg", "rice: 2 kg").
    private static let separators: Set<Character> = ["-", "–", "—", ":", "=", ",", "@", "|"]

    private static func joinedName(_ tokens: ArraySlice<QuantityToken>) -> String {
        var words = tokens.map { String($0.text) }
        while let last = words.last, last.allSatisfy({ separators.contains($0) }) { words.removeLast() }
        if var last = words.popLast() {
            while let character = last.last, separators.contains(character) { last.removeLast() }
            if !last.isEmpty { words.append(last) }
        }
        return words.joined(separator: " ")
    }

    /// A number at `index`, including a mixed number "1 1/2": its value and token count.
    private static func number(_ tokens: [QuantityToken], at index: Int) -> (Double, Int)? {
        guard index < tokens.count, case .number(let whole, let isFraction) = tokens[index].kind else { return nil }
        if !isFraction, index + 1 < tokens.count, case .number(let part, true) = tokens[index + 1].kind, part < 1 {
            return (whole + part, 2)
        }
        return (whole, 1)
    }

    /// "2 kg rice", "2kg rice", "2 x milk", "2x milk", "a dozen eggs", "dozen eggs", "two onions",
    /// "1 1/2 kg of rice".
    private static func leadingQuantity(_ tokens: [QuantityToken]) -> Extracted? {
        guard let first = tokens.first else { return nil }
        var amount = 0.0
        var unit: MeasureUnit?
        var next = 0
        if let leading = number(tokens, at: 0) {
            (amount, next) = leading
            if next < tokens.count {
                switch tokens[next].kind {
                case .unit(let found):
                    unit = found
                    next += 1
                case .times:
                    next += 1
                default: break
                }
            }
        } else {
            switch first.kind {
            case .numberWithUnit(let value, let found):
                amount = value
                unit = found
                next = 1
            case .numberTimes(let value):
                (amount, next) = (value, 1)
            case .unit(.dozen):
                amount = 1
                unit = .dozen
                next = 1
            case .numberWord(let value, let needsUnit):
                if tokens.count > 1, case .unit(let found) = tokens[1].kind {
                    amount = value
                    unit = found
                    next = 2
                } else if !needsUnit {
                    (amount, next) = (value, 1)
                } else {
                    return nil
                }
            default:
                return nil
            }
        }
        if next < tokens.count, tokens[next].text.lowercased() == "of" { next += 1 }
        let name = joinedName(tokens[next...])
        return name.isEmpty ? nil : Extracted(name: name, amount: amount, unit: unit)
    }

    /// "rice - 2kg", "rice 2 kg", "milk x2", "milk x 2", "milk 2x", "eggs 12", "eggs (12)",
    /// "rice (2 kg)", "eggs one dozen".
    private static func trailingQuantity(_ body: Substring, _ tokens: [QuantityToken]) -> Extracted? {
        if body.last == ")", let open = body.lastIndex(of: "(") {
            let inner = body[body.index(after: open)..<body.index(before: body.endIndex)]
            let innerTokens = inner.split(whereSeparator: { $0.isWhitespace }).map(QuantityToken.init)
            let before = body[..<open].split(whereSeparator: { $0.isWhitespace }).map(QuantityToken.init)
            if let quantity = standaloneQuantity(innerTokens) {
                let name = joinedName(before[...])
                return name.isEmpty ? nil : Extracted(name: name, amount: quantity.0, unit: quantity.1)
            }
            return nil
        }
        let count = tokens.count
        guard count >= 2 else { return nil }
        var amount = 0.0
        var unit: MeasureUnit?
        var nameEnd = 0
        switch tokens[count - 1].kind {
        case .numberWithUnit(let value, let found):
            amount = value
            unit = found
            nameEnd = count - 1
        case .timesNumber(let value), .numberTimes(let value):
            (amount, nameEnd) = (value, count - 1)
        case .unit(let found):
            guard let trailing = trailingNumber(tokens, endingBefore: count - 1) else { return nil }
            amount = trailing.0
            unit = found
            nameEnd = trailing.1
        case .number:
            guard let trailing = trailingNumber(tokens, endingBefore: count) else { return nil }
            (amount, nameEnd) = trailing
            if nameEnd > 0, tokens[nameEnd - 1].kind == .times { nameEnd -= 1 }
        default:
            return nil
        }
        let name = joinedName(tokens[..<nameEnd])
        return name.isEmpty ? nil : Extracted(name: name, amount: amount, unit: unit)
    }

    /// The number that ends just before `end` (a plain number, a mixed number or a number word):
    /// its value and the index of its first token.
    private static func trailingNumber(_ tokens: [QuantityToken], endingBefore end: Int) -> (Double, Int)? {
        guard end >= 1 else { return nil }
        if end >= 2, let mixed = number(tokens, at: end - 2), mixed.1 == 2 { return (mixed.0, end - 2) }
        switch tokens[end - 1].kind {
        case .number(let value, _): return (value, end - 1)
        case .numberWord(let value, _) where end < tokens.count: return (value, end - 1)
        default: return nil
        }
    }

    /// The whole of `tokens` as a quantity ("12", "2 kg", "2kg", "1 dozen", "x2"), or nil.
    private static func standaloneQuantity(_ tokens: [QuantityToken]) -> (Double, MeasureUnit?)? {
        switch tokens.count {
        case 1:
            switch tokens[0].kind {
            case .number(let value, _), .timesNumber(let value), .numberTimes(let value): return (value, nil)
            case .numberWithUnit(let value, let unit): return (value, unit)
            case .unit(.dozen): return (1, .dozen)
            default: return nil
            }
        case 2, 3:
            guard case .unit(let unit) = tokens[tokens.count - 1].kind else {
                if tokens.count == 2, let mixed = number(tokens, at: 0), mixed.1 == 2 { return (mixed.0, nil) }
                return nil
            }
            if let found = number(tokens, at: 0), found.1 == tokens.count - 1 { return (found.0, unit) }
            if tokens.count == 2, case .numberWord(let value, _) = tokens[0].kind { return (value, unit) }
            return nil
        default:
            return nil
        }
    }

    // MARK: - Confidence

    private static func classify(name: String, hasQuantity: Bool) -> ParsedShoppingLine.Confidence {
        guard name.contains(where: { $0.isLetter }) else { return .unsure }
        if name.count > maxItemNameLength || name.hasSuffix(":") || name.hasSuffix("?") { return .unsure }
        let lower = name.lowercased()
        if lower.contains("http://") || lower.contains("https://") || lower.contains("www.") { return .unsure }
        let lowerWords = lower.split(whereSeparator: { !$0.isLetter }).map(String.init)
        if lowerWords.contains(where: { nonItemCueWords.contains($0) }) { return .unsure }
        let wordCount = name.split(whereSeparator: { $0.isWhitespace }).count
        if !hasQuantity, wordCount > maxItemWordsWithoutQuantity { return .unsure }
        return .item
    }
}
