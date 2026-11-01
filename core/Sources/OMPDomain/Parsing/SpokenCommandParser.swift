import Foundation

/// One pantry item heard in a spoken command (ADR 0012, AC-9.4). Shown on the confirmation card
/// (S-22); nothing is saved until the user confirms.
public struct SpokenPantryItem: Sendable, Hashable {
    /// The words for this item as heard, amount included ("2 kg rice"). Prefills the manual form.
    public let spokenText: String
    /// The item words without the amount, lowercased ("rice").
    public let name: String
    /// The amount, if one was said. With no `unit` it is a count: "a dozen eggs" is 12.
    public let qty: Double?
    public let unit: MeasureUnit?
    /// The best taxonomy candidate for `name`.
    public let match: IngredientResolver.Candidate
    /// True when `match` is the resolver's confident match; otherwise the card asks the user to
    /// check the ingredient.
    public let isConfident: Bool

    public init(
        spokenText: String, name: String, qty: Double?, unit: MeasureUnit?, match: IngredientResolver.Candidate,
        isConfident: Bool
    ) {
        self.spokenText = spokenText
        self.name = name
        self.qty = qty
        self.unit = unit
        self.match = match
        self.isConfident = isConfident
    }

    /// The amount as a `Quantity`; a bare count is in pieces.
    public var quantity: Quantity? {
        guard let qty else { return nil }
        return Quantity(qty, unit ?? .piece)
    }
}

/// What a spoken sentence asks for (ADR 0012).
///
/// There is deliberately no "approve" case: "approve it" or "looks good" only opens the approval
/// sheet, which still needs a confirming tap (AC-5.6). No grammar path can approve a plan.
public enum SpokenCommand: Sendable, Hashable {
    /// "I bought ...", "add ...", "picked up ...".
    case add([SpokenPantryItem])
    /// "we're out of ...", "used up ...", "finished ...".
    case markOut([SpokenPantryItem])
    /// "remove ...", "delete ...".
    case remove([SpokenPantryItem])
    /// "approve", "approve the plan", "looks good": open the approval sheet, nothing more.
    case openApprovalSheet
}

/// The commands in one transcript plus what was not understood.
public struct SpokenCommandParseResult: Sendable, Hashable {
    /// In the order they were said. `.openApprovalSheet` appears at most once.
    public let commands: [SpokenCommand]
    /// Pieces of the transcript that were not understood, in order, as heard. The UI shows them
    /// under "I didn't catch" and offers the manual form prefilled with them (S-22, G9).
    public let unparsed: [String]
    /// True when the transcript was longer than `SpokenCommandParser.maxTranscriptLength`; the
    /// rest was not parsed.
    public let wasTruncated: Bool

    public init(commands: [SpokenCommand], unparsed: [String], wasTruncated: Bool) {
        self.commands = commands
        self.unparsed = unparsed
        self.wasTruncated = wasTruncated
    }

    /// The unparsed pieces as one string, for the manual form.
    public var unparsedText: String { unparsed.joined(separator: " ") }

    /// Every item of every pantry command, in order.
    public var pantryItems: [SpokenPantryItem] {
        commands.flatMap { command -> [SpokenPantryItem] in
            switch command {
            case .add(let items), .markOut(let items), .remove(let items): return items
            case .openApprovalSheet: return []
            }
        }
    }
}

/// The deterministic voice command grammar (ADR 0012, G9). Pure and locale-independent.
///
/// ```
/// ADD     := SUBJECT? (bought | got | picked up | add | added | purchased) ITEMLIST
/// OUT     := SUBJECT? (out of | are out of | we're out of | ran/run out of | used up | finished | no more) ITEMLIST
/// REMOVE  := SUBJECT? (remove | delete) ITEMLIST
/// APPROVE := (that|it|ok|...)? (approve (it|the plan|...)? | looks good (to me)?)  -> .openApprovalSheet
/// ITEMLIST := ITEM ((, | and | plus) ITEM)*
/// ITEM     := QTY? UNIT? (of)? NAME
/// ```
/// Numbers are digits (`2`, `1.5`, `1/2`, `½`, `2kg`), words (one to nineteen, twenty to ninety,
/// "twenty five", "two hundred and fifty"), "a/an", "half", "a quarter", "a couple", "a dozen",
/// "one and a half", "half a kilo". A dozen is a count of 12.
///
/// An item becomes a pantry item only when its name has at least one `IngredientResolver`
/// candidate; anything else (and any words outside a command) is returned in `unparsed`.
/// Sentences split on `.`, `!`, `?`, `;` and new lines; a new command verb also starts a command.
public struct SpokenCommandParser: Sendable {
    /// Transcripts are cut to this many characters (untrusted input).
    public static let maxTranscriptLength = 2_000

    private let resolver: IngredientResolver

    public init(resolver: IngredientResolver) {
        self.resolver = resolver
    }

    public func parse(_ input: String) -> SpokenCommandParseResult {
        let transcript = TranscriptSanitiser.sanitise(input)
        let capped = transcript.prefix(SpokenCommandParser.maxTranscriptLength)
        let wasTruncated = capped.endIndex != transcript.endIndex
        let tokens = SpokenCommandParser.tokenize(capped)
        let keys = tokens.map(\.key)

        var commands: [SpokenCommand] = []
        var unparsed: [String] = []
        var pending: [SpokenToken] = []

        func flushPending() {
            if let text = SpokenCommandParser.meaningfulText(pending) { unparsed.append(text) }
            pending.removeAll()
        }

        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .boundary {
                flushPending()
                index += 1
                continue
            }
            guard let verb = SpokenCommandParser.matchVerb(keys, at: index) else {
                if token.kind == .word { pending.append(token) }
                index += 1
                continue
            }
            flushPending()
            let verbEnd = index + verb.length
            if verb.kind == .approve {
                if !commands.contains(.openApprovalSheet) { commands.append(.openApprovalSheet) }
                index = verbEnd
                continue
            }
            var end = verbEnd
            while end < tokens.count, tokens[end].kind != .boundary,
                SpokenCommandParser.matchVerb(keys, at: end) == nil
            {
                end += 1
            }
            var items: [SpokenPantryItem] = []
            var notUnderstood: [String] = []
            for itemTokens in SpokenCommandParser.splitItems(Array(tokens[verbEnd..<end])) {
                if let item = parseItem(itemTokens) {
                    items.append(item)
                } else if let text = SpokenCommandParser.meaningfulText(itemTokens) {
                    notUnderstood.append(text)
                }
            }
            if items.isEmpty {
                let whole = tokens[index..<end].filter { $0.kind == .word }
                if let text = SpokenCommandParser.meaningfulText(Array(whole)) { unparsed.append(text) }
            } else {
                switch verb.kind {
                case .add: commands.append(.add(items))
                case .out: commands.append(.markOut(items))
                case .remove: commands.append(.remove(items))
                case .approve: break
                }
                unparsed += notUnderstood
            }
            index = end
        }
        flushPending()
        return SpokenCommandParseResult(commands: commands, unparsed: unparsed, wasTruncated: wasTruncated)
    }

    // MARK: - Items

    /// One item ("2 kg rice"), or nil when it has no name or the name matches no ingredient.
    private func parseItem(_ tokens: [SpokenToken]) -> SpokenPantryItem? {
        let keys = tokens.map(\.key)
        let start = SpokenCommandParser.skipPhrases(keys, from: 0, SpokenLexicon.leadingFillers)
        let amount = SpokenCommandParser.parseAmount(keys, from: start)
        var nameStart = amount.next
        while nameStart < keys.count, keys[nameStart] == "of" || keys[nameStart] == "the" { nameStart += 1 }
        var nameEnd = keys.count
        var trimmed = true
        while trimmed {
            trimmed = false
            for phrase in SpokenLexicon.trailingFillers
            where nameEnd - phrase.count >= nameStart
                && SpokenCommandParser.matches(keys, phrase, at: nameEnd - phrase.count)
            {
                nameEnd -= phrase.count
                trimmed = true
                break
            }
        }
        guard nameStart < nameEnd else { return nil }
        let name = keys[nameStart..<nameEnd].joined(separator: " ")
        guard name.contains(where: { $0.isLetter }) else { return nil }

        let confident = resolver.confidentMatch(for: name)
        guard let match = confident ?? resolver.candidates(for: name, limit: 1).first else { return nil }

        var qty = amount.qty
        var unit = amount.unit
        if let current = unit, !current.isQuantified {
            qty = nil
            unit = nil
        }
        let spoken = tokens.map(\.raw).joined(separator: " ")
        return SpokenPantryItem(
            spokenText: spoken, name: name, qty: qty, unit: unit, match: match, isConfident: confident != nil)
    }

    /// Splits an item list on commas, "and" and "plus", except the "and" inside a number
    /// ("one and a half", "two hundred and fifty").
    static func splitItems(_ tokens: [SpokenToken]) -> [[SpokenToken]] {
        let keys = tokens.map(\.key)
        var items: [[SpokenToken]] = [[]]
        for (offset, token) in tokens.enumerated() {
            let isSeparator =
                token.kind == .comma || keys[offset] == "plus"
                || (keys[offset] == "and" && !andContinuesNumber(keys, at: offset))
            if isSeparator {
                if !(items.last ?? []).isEmpty { items.append([]) }
                continue
            }
            if token.kind == .word { items[items.count - 1].append(token) }
        }
        return items.filter { !$0.isEmpty }
    }

    private static func andContinuesNumber(_ keys: [String], at index: Int) -> Bool {
        guard index > 0, index + 1 < keys.count else { return false }
        let previous = keys[index - 1]
        let next = keys[index + 1]
        if previous == "hundred" { return SpokenLexicon.isNumberWord(next) }
        let previousIsNumber =
            digitNumber(previous) != nil || SpokenLexicon.isNumberWord(previous) || previous == "half"
        guard previousIsNumber else { return false }
        if next == "half" || next == "quarter" { return true }
        if next == "a", index + 2 < keys.count { return keys[index + 2] == "half" || keys[index + 2] == "quarter" }
        return false
    }

    // MARK: - Amounts

    struct Amount: Equatable {
        var qty: Double?
        var unit: MeasureUnit?
        var next: Int
    }

    /// The amount at the start of an item: "2 kg", "2kg", "a dozen", "half a kilo", "one and a
    /// half kg", "two hundred and fifty grams", "a couple", "an". `next` is the first name token.
    static func parseAmount(_ keys: [String], from start: Int) -> Amount {
        func key(_ index: Int) -> String? { index < keys.count ? keys[index] : nil }
        var index = start
        var value: Double?
        var unit: MeasureUnit?

        func apply(_ found: MeasureUnit) {
            if found == .dozen {
                value = (value ?? 1) * 12
                unit = nil
            } else {
                if value == nil { value = 1 }
                unit = found
            }
        }

        guard let first = key(index) else { return Amount(qty: nil, unit: nil, next: index) }
        if let couple = SpokenLexicon.couplePhrases.first(where: { matches(keys, $0, at: index) }) {
            value = 2
            index += couple.count
        } else if let combined = digitNumberWithUnit(first) {
            value = combined.0
            index += 1
            apply(combined.1)
            return Amount(qty: value, unit: unit, next: index)
        } else if let number = digitNumber(first) {
            value = number
            index += 1
        } else if let words = wordNumber(keys, from: index) {
            value = words.value
            index = words.next
        } else if first == "half" {
            value = 0.5
            index += 1
        } else if first == "quarter" {
            value = 0.25
            index += 1
        } else if first == "a" || first == "an" {
            if key(index + 1) == "half" {
                value = 0.5
                index += 2
            } else if key(index + 1) == "quarter" {
                value = 0.25
                index += 2
            } else {
                value = 1
                index += 1
            }
        }

        if let whole = value {
            // "1 1/2", "1 ½"
            if whole >= 1, let next = key(index), let part = digitNumber(next), part < 1 {
                value = whole + part
                index += 1
            }
            // "and a half", "and half", "and a quarter"
            if key(index) == "and" {
                if key(index + 1) == "half" {
                    value = (value ?? 0) + 0.5
                    index += 2
                } else if key(index + 1) == "a", key(index + 2) == "half" {
                    value = (value ?? 0) + 0.5
                    index += 3
                } else if key(index + 1) == "a", key(index + 2) == "quarter" {
                    value = (value ?? 0) + 0.25
                    index += 3
                }
            }
            // "half a kilo", "a couple of kilos"
            if let next = key(index), next == "a" || next == "an" || next == "of",
                let after = key(index + 1), unitWord(after) != nil
            {
                index += 1
            }
            if let next = key(index), let found = unitWord(next) {
                apply(found)
                index += 1
            }
        } else if let found = unitWord(first) {
            // "dozen eggs", "kilo of rice"
            apply(found)
            index += 1
        }
        return Amount(qty: value, unit: unit, next: index)
    }

    /// A whole token that is a digit number: "2", "1.5", "1/2", "½".
    static func digitNumber(_ key: String) -> Double? {
        let characters = Array(key)
        guard let scanned = QuantityLexicon.scanNumber(characters), scanned.length == characters.count else {
            return nil
        }
        return scanned.value
    }

    /// A digit number glued to a unit: "2kg", "500g", "½kg".
    static func digitNumberWithUnit(_ key: String) -> (Double, MeasureUnit)? {
        let characters = Array(key)
        guard let scanned = QuantityLexicon.scanNumber(characters), scanned.length < characters.count,
            let unit = QuantityLexicon.unit(Substring(String(characters[scanned.length...])))
        else { return nil }
        return (scanned.value, unit)
    }

    static func unitWord(_ key: String) -> MeasureUnit? {
        QuantityLexicon.unit(Substring(key))
    }

    /// Number words starting at `start`: "five", "twenty five", "two hundred and fifty",
    /// "a hundred". Nil when there is none.
    static func wordNumber(_ keys: [String], from start: Int) -> (value: Double, next: Int)? {
        func key(_ index: Int) -> String? { index < keys.count ? keys[index] : nil }
        var index = start
        var total = 0.0
        var matched = false
        if let first = key(index), key(index + 1) == "hundred",
            let multiplier = SpokenLexicon.ones[first] ?? ((first == "a" || first == "an") ? 1 : nil)
        {
            total = multiplier * 100
            index += 2
            matched = true
        } else if key(index) == "hundred" {
            total = 100
            index += 1
            matched = true
        }
        if matched, key(index) == "and", let next = key(index + 1), SpokenLexicon.isNumberWord(next),
            next != "hundred"
        {
            index += 1
        }
        if let word = key(index), let tens = SpokenLexicon.tens[word] {
            total += tens
            index += 1
            matched = true
            if let word = key(index), let ones = SpokenLexicon.ones[word] {
                total += ones
                index += 1
            }
        } else if let word = key(index), let small = SpokenLexicon.ones[word] ?? SpokenLexicon.teens[word] {
            total += small
            index += 1
            matched = true
        }
        guard matched, total > 0 else { return nil }
        return (total, index)
    }

    // MARK: - Verbs

    enum VerbKind: Sendable, Equatable {
        case add
        case out
        case remove
        case approve
    }

    /// The command verb phrase starting at `index` and its length in tokens, if any.
    static func matchVerb(_ keys: [String], at index: Int) -> (kind: VerbKind, length: Int)? {
        guard index < keys.count else { return nil }
        for phrase in SpokenLexicon.approvePhrases where matches(keys, phrase, at: index) {
            return (.approve, phrase.count)
        }
        for subject in SpokenLexicon.subjects where matches(keys, subject, at: index) {
            let coreStart = index + subject.count
            for core in SpokenLexicon.verbCores where matches(keys, core.words, at: coreStart) {
                return (core.kind, subject.count + core.words.count)
            }
        }
        return nil
    }

    static func matches(_ keys: [String], _ phrase: [String], at index: Int) -> Bool {
        guard index >= 0, index + phrase.count <= keys.count else { return false }
        for (offset, word) in phrase.enumerated() where keys[index + offset] != word {
            return false
        }
        return true
    }

    /// The index after any of `phrases` repeated from `start` (longest phrase first).
    static func skipPhrases(_ keys: [String], from start: Int, _ phrases: [[String]]) -> Int {
        var index = start
        var skipped = true
        while skipped, index < keys.count {
            skipped = false
            for phrase in phrases where matches(keys, phrase, at: index) {
                index += phrase.count
                skipped = true
                break
            }
        }
        return index
    }

    /// The tokens as heard, or nil when they are only filler words ("um", "okay so", "and").
    static func meaningfulText(_ tokens: [SpokenToken]) -> String? {
        let words = tokens.filter { $0.kind == .word }
        guard words.contains(where: { !SpokenLexicon.fillers.contains($0.key) }) else { return nil }
        return words.map(\.raw).joined(separator: " ")
    }

    // MARK: - Tokens

    /// Splits a transcript into words, commas and sentence boundaries. Keys are lowercased with
    /// apostrophes removed ("We're" -> "were"); "." and "/" stay inside numbers ("1.5", "1/2").
    static func tokenize(_ text: Substring) -> [SpokenToken] {
        let characters = Array(text)
        var tokens: [SpokenToken] = []
        var current = ""

        func flush() {
            guard !current.isEmpty else { return }
            let key = String(current.lowercased().filter { !SpokenLexicon.apostrophes.contains($0) })
            if !key.isEmpty { tokens.append(SpokenToken(kind: .word, raw: current, key: key)) }
            current = ""
        }

        for index in characters.indices {
            let character = characters[index]
            if character == "." || character == "/" {
                let previousIsDigit = index > 0 && isASCIIDigit(characters[index - 1])
                let nextIsDigit = index + 1 < characters.count && isASCIIDigit(characters[index + 1])
                if previousIsDigit && nextIsDigit {
                    current.append(character)
                    continue
                }
            }
            if character == "," {
                flush()
                tokens.append(SpokenToken(kind: .comma, raw: ",", key: ","))
            } else if character.isNewline || SpokenLexicon.sentenceEnds.contains(character) {
                flush()
                tokens.append(SpokenToken(kind: .boundary, raw: ".", key: "."))
            } else if character == "&" || character == "+" {
                flush()
                tokens.append(SpokenToken(kind: .word, raw: String(character), key: "and"))
            } else if character.isLetter || character.isNumber || SpokenLexicon.apostrophes.contains(character) {
                current.append(character)
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        guard let ascii = character.asciiValue else { return false }
        return ascii >= 48 && ascii <= 57
    }
}

/// One token of a transcript.
struct SpokenToken: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case word
        case comma
        case boundary
    }

    let kind: Kind
    /// As heard (original casing and apostrophes).
    let raw: String
    /// Lowercased, apostrophes removed.
    let key: String
}

/// The fixed vocabulary of the voice grammar (ADR 0012). Keys are lowercased without apostrophes.
enum SpokenLexicon {
    static let apostrophes: Set<Character> = ["'", "\u{2019}", "`"]
    static let sentenceEnds: Set<Character> = [".", "!", "?", ";"]

    static let ones: [String: Double] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
    ]
    static let teens: [String: Double] = [
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    static let tens: [String: Double] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80,
        "ninety": 90,
    ]

    static func isNumberWord(_ key: String) -> Bool {
        ones[key] != nil || teens[key] != nil || tens[key] != nil || key == "hundred"
    }

    /// "a couple (of)", "a pair (of)": 2. The "of" is left for the name step.
    static let couplePhrases: [[String]] = [["a", "couple"], ["couple"], ["a", "pair"], ["pair"]]

    /// Optional words before a command verb, longest first.
    static let subjects: [[String]] = {
        let list: [[String]] = [
            [], ["i"], ["we"], ["ive"], ["weve"], ["im"], ["i", "have"], ["we", "have"], ["i", "just"], ["we", "just"],
            ["just"], ["i", "also"], ["we", "also"], ["also"], ["please"], ["can", "you"], ["could", "you"],
            ["ive", "just"], ["weve", "just"], ["ive", "also"], ["weve", "also"], ["i", "have", "just"],
            ["we", "have", "just"], ["theres"], ["there", "is"], ["i", "am"], ["we", "are"],
        ]
        return list.sorted { $0.count > $1.count }
    }()

    /// Command verbs, longest first so "ran out of" wins over shorter phrases.
    static let verbCores: [(words: [String], kind: SpokenCommandParser.VerbKind)] = {
        let list: [([String], SpokenCommandParser.VerbKind)] = [
            (["bought"], .add), (["got"], .add), (["picked", "up"], .add), (["add"], .add), (["added"], .add),
            (["purchased"], .add),
            (["out", "of"], .out), (["are", "out", "of"], .out), (["were", "out", "of"], .out),
            (["am", "out", "of"], .out), (["are", "all", "out", "of"], .out), (["all", "out", "of"], .out),
            (["ran", "out", "of"], .out), (["run", "out", "of"], .out), (["used", "up"], .out),
            (["finished"], .out), (["no", "more"], .out),
            (["remove"], .remove), (["delete"], .remove),
        ]
        return list.sorted { $0.0.count > $1.0.count }.map { (words: $0.0, kind: $0.1) }
    }()

    /// Phrases that open the approval sheet (never approve: AC-5.6), longest first.
    static let approvePhrases: [[String]] = {
        var phrases: [[String]] = []
        let approvePrefixes: [[String]] = [[], ["please"], ["ok"], ["okay"], ["yes"], ["lets"], ["go", "ahead", "and"]]
        let approveTails: [[String]] = [
            [], ["it"], ["this"], ["that"], ["the", "plan"], ["plan"], ["this", "plan"], ["the", "week"],
            ["this", "week"], ["the", "meal", "plan"],
        ]
        for prefix in approvePrefixes {
            for tail in approveTails {
                phrases.append(prefix + ["approve"] + tail)
            }
            phrases.append(prefix + ["approved"])
        }
        let goodPrefixes: [[String]] = [
            [], ["that"], ["it"], ["this"], ["plan"], ["the", "plan"], ["that", "plan"], ["ok"], ["okay"], ["yes"],
        ]
        for prefix in goodPrefixes {
            phrases.append(prefix + ["looks", "good"])
            phrases.append(prefix + ["looks", "good", "to", "me"])
        }
        return phrases.sorted { $0.count > $1.count }
    }()

    /// Words before an item's amount that carry no meaning ("then", "some", "a few"), longest first.
    static let leadingFillers: [[String]] = {
        let list: [[String]] = [
            ["a", "little", "bit", "of"], ["a", "bit", "of"], ["a", "lot", "of"], ["a", "few"], ["a", "little"],
            ["a", "bit"], ["lots", "of"], ["the"], ["some"], ["more"], ["of"], ["then"], ["also"], ["my"], ["our"],
            ["just"], ["please"],
        ]
        return list.sorted { $0.count > $1.count }
    }()

    /// Words after an item's name that carry no meaning ("to the pantry", "please"), longest first.
    static let trailingFillers: [[String]] = {
        let list: [[String]] = [
            ["to", "the", "pantry"], ["into", "the", "pantry"], ["in", "the", "pantry"], ["from", "the", "pantry"],
            ["to", "pantry"], ["from", "pantry"], ["as", "well"], ["please"], ["too"], ["today"], ["yesterday"],
            ["now"], ["again"],
        ]
        return list.sorted { $0.count > $1.count }
    }()

    /// Words that are dropped when nothing else around them was understood ("um, okay so").
    static let fillers: Set<String> = [
        "um", "umm", "uh", "uhh", "erm", "er", "hmm", "ah", "oh", "okay", "ok", "so", "and", "then", "also", "well",
        "hey", "please", "yeah", "yes", "right", "thanks", "thank", "you", "lets", "now", "just", "alright", "plus",
        "the", "some", "more", "of", "my", "our", "i", "we", "it", "that", "this", "is", "a", "an",
    ]
}
