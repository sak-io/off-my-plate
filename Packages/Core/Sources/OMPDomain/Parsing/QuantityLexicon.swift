/// The words and number shapes the rule-based parsers understand (plan section 8, task T15).
///
/// Everything here is locale-independent: only ASCII digits are numbers, unit words are matched
/// after `lowercased()` (which does not depend on the user's locale), and decimals use ".".
enum QuantityLexicon {
    /// Unit spellings seen in Indian shopping notes, keyed by their lowercased form without a
    /// trailing ".". Packs and bunches count as pieces: the name keeps what is being counted.
    static let units: [String: MeasureUnit] = {
        var table: [String: MeasureUnit] = [:]
        func add(_ unit: MeasureUnit, _ spellings: [String]) {
            for spelling in spellings { table[spelling] = unit }
        }
        add(.gram, ["g", "gm", "gms", "gr", "grm", "grms", "gram", "grams", "gramme", "grammes"])
        add(.kilogram, ["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms", "kilogramme", "kilogrammes"])
        add(.millilitre, ["ml", "mls", "millilitre", "millilitres", "milliliter", "milliliters"])
        add(.litre, ["l", "lt", "ltr", "ltrs", "litre", "litres", "liter", "liters"])
        add(.teaspoon, ["tsp", "tsps", "teaspoon", "teaspoons"])
        add(.tablespoon, ["tbsp", "tbsps", "tbs", "tablespoon", "tablespoons"])
        add(.cup, ["cup", "cups"])
        add(.piece, [
            "pc", "pcs", "piece", "pieces", "nos", "packet", "packets", "pack", "packs", "pkt", "pkts", "bunch",
            "bunches",
        ])
        add(.dozen, ["dozen", "dozens", "doz", "dz"])
        // Non-quantified: recognised so "hing 1 pinch" reads as "hing", then the amount is dropped.
        add(.pinch, ["pinch", "pinches"])
        return table
    }()

    /// Number words that may start a line ("two onions", "a dozen eggs", "half kg tomatoes").
    /// `a`, `an` and `half` count only when a unit follows, so names are not misread.
    static let numberWords: [String: Double] = [
        "a": 1, "an": 1, "half": 0.5, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
    ]
    static let numberWordsNeedingUnit: Set<String> = ["a", "an", "half"]

    /// Unicode vulgar fractions ("½ kg", "1½ kg").
    static let vulgarFractions: [Character: Double] = [
        "½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3.0, "⅔": 2.0 / 3.0, "⅛": 0.125,
    ]

    /// Multiplication signs in "milk x2", "2 x milk", "2× milk".
    static let timesSigns: Set<Character> = ["x", "X", "×", "*"]

    /// Longest digit runs accepted, so huge numbers stay text and never overflow.
    static let maxIntegerDigits = 6
    static let maxFractionDigits = 3

    static func unit(_ word: Substring) -> MeasureUnit? {
        var key = word.lowercased()
        if key.hasSuffix(".") { key.removeLast() }
        return units[key]
    }

    /// Scans a number at the start of `chars`: `12`, `1.5`, `1/2`, `½`, `1½`. Returns its value
    /// (finite, > 0) and how many characters it used, or nil.
    static func scanNumber(_ chars: [Character]) -> (value: Double, length: Int)? {
        var index = 0
        let integer = digitRun(chars, from: &index)
        var value: Double
        if let integer {
            guard integer.count <= maxIntegerDigits, let whole = Double(integer) else { return nil }
            value = whole
            if index + 1 < chars.count, chars[index] == "." {
                var probe = index + 1
                if let fraction = digitRun(chars, from: &probe) {
                    guard fraction.count <= maxFractionDigits, let decimal = Double(integer + "." + fraction) else {
                        return nil
                    }
                    value = decimal
                    index = probe
                }
            } else if index + 1 < chars.count, chars[index] == "/" {
                var probe = index + 1
                if let denominatorText = digitRun(chars, from: &probe) {
                    guard denominatorText.count <= maxFractionDigits, let denominator = Double(denominatorText),
                        denominator > 0
                    else { return nil }
                    value = whole / denominator
                    index = probe
                }
            } else if index < chars.count, let vulgar = vulgarFractions[chars[index]] {
                value += vulgar
                index += 1
            }
        } else if let first = chars.first, let vulgar = vulgarFractions[first] {
            value = vulgar
            index = 1
        } else {
            return nil
        }
        guard value.isFinite, value > 0 else { return nil }
        return (value, index)
    }

    /// ASCII digits starting at `index` (advanced past them), or nil when there are none.
    private static func digitRun(_ chars: [Character], from index: inout Int) -> String? {
        var run = ""
        while index < chars.count, let ascii = chars[index].asciiValue, ascii >= 48, ascii <= 57 {
            run.append(chars[index])
            index += 1
        }
        return run.isEmpty ? nil : run
    }
}

/// One whitespace-separated word of a line, classified for quantity parsing.
struct QuantityToken {
    enum Kind: Equatable {
        /// `2`, `1.5`, `1/2`, `½`. `isFraction` marks `1/2` and `½` (the tail of "1 1/2").
        case number(Double, isFraction: Bool)
        /// `2kg`, `500g`, `½kg`.
        case numberWithUnit(Double, MeasureUnit)
        /// `2x`, `2×`.
        case numberTimes(Double)
        /// `x2`, `×2`.
        case timesNumber(Double)
        case unit(MeasureUnit)
        case times
        /// `two`, `a`, `half` (see `QuantityLexicon.numberWords`).
        case numberWord(Double, needsUnit: Bool)
        case word
    }

    let text: Substring
    let kind: Kind

    init(_ text: Substring) {
        self.text = text
        self.kind = QuantityToken.classify(text)
    }

    private static func classify(_ text: Substring) -> Kind {
        let chars = Array(text)
        if chars.count == 1, QuantityLexicon.timesSigns.contains(chars[0]) { return .times }
        if let scanned = QuantityLexicon.scanNumber(chars) {
            let rest = chars[scanned.length...]
            if rest.isEmpty {
                let isFraction = chars.contains("/") || chars.contains { QuantityLexicon.vulgarFractions[$0] != nil }
                return .number(scanned.value, isFraction: isFraction)
            }
            if rest.count == 1, let sign = rest.first, QuantityLexicon.timesSigns.contains(sign) {
                return .numberTimes(scanned.value)
            }
            if let unit = QuantityLexicon.unit(Substring(String(rest))) { return .numberWithUnit(scanned.value, unit) }
            return .word
        }
        if chars.count > 1, QuantityLexicon.timesSigns.contains(chars[0]),
            let scanned = QuantityLexicon.scanNumber(Array(chars[1...])), scanned.length == chars.count - 1
        {
            return .timesNumber(scanned.value)
        }
        if let unit = QuantityLexicon.unit(text) { return .unit(unit) }
        let lower = text.lowercased()
        if let value = QuantityLexicon.numberWords[lower] {
            return .numberWord(value, needsUnit: QuantityLexicon.numberWordsNeedingUnit.contains(lower))
        }
        return .word
    }
}
