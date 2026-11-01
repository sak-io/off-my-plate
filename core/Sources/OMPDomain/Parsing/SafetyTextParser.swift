import Foundation

/// One thing the user typed or said on the safety screen (S-02), shown back as a candidate hard
/// rule. Nothing is saved until the user confirms (AC-2.3).
public enum SafetyCandidate: Sendable, Hashable {
    /// The text selects this catalog restriction. One word may select several ("nuts" selects
    /// peanuts and tree nuts); each is its own candidate.
    /// - matchedText: the words that matched, as typed ("nuts").
    /// - memberHint: a name the user mentioned ("Meera"). Only a hint for the "Who?" menu; it is
    ///   never a restriction and never assigns the rule by itself (G3).
    case restriction(RestrictionID, matchedText: String, memberHint: String?)
    /// Text the parser could not map to a restriction. The UI must make the user pick a
    /// restriction or remove the row (AC-2.4); it is never dropped and never means "safe".
    case unmapped(text: String, memberHint: String?)

    public var memberHint: String? {
        switch self {
        case .restriction(_, _, let hint), .unmapped(_, let hint): return hint
        }
    }

    public var isUnmapped: Bool {
        if case .unmapped = self { return true }
        return false
    }
}

/// Turns free text from the safety question into candidate restrictions (plan section 8,
/// AC-2.3, AC-2.4). Pure and locale-independent.
///
/// The keyword table comes from the seed catalog (`SeedCatalog.restrictionKeywords`, owner
/// signed off, R4), passed in because OMPDomain does not depend on OMPRecipes. Keywords match
/// longest first, with or without a plural "s" ("tree nuts", "almonds").
///
/// The text is split into clauses on punctuation and on "and", "or", "but", "plus", "also".
/// In each clause, catalog keywords become `.restriction` candidates, known grammar words
/// ("no", "can't have", "allergy") are skipped (`ignoredWords`), and every other run of words
/// becomes `.unmapped`. A clause with no candidate at all becomes one `.unmapped` with its whole
/// text, so nothing the user wrote is lost. Text beyond `maxInputLength` is returned as an
/// `.unmapped` too.
///
/// A member name is recognised in "Meera has a nut allergy", "Meera's nut allergy",
/// "Meera: no nuts" and "no nuts for Meera", but only when the rest of the clause names at least
/// one restriction; otherwise the name stays in the text as `.unmapped`.
public struct SafetyTextParser: Sendable {
    /// Input is cut to this many characters; the rest becomes one `.unmapped` candidate.
    public static let maxInputLength = 2_000
    /// Longest text of the `.unmapped` candidate that stands for input beyond the cap.
    static let overflowPreviewLength = 60
    /// A member hint has at most this many words.
    static let maxHintWords = 3

    /// Normalised keyword -> restrictions, in table order without duplicates.
    private let exact: [String: [RestrictionID]]
    /// The same, keyed by the singular of every word ("almonds" finds "almond").
    private let singular: [String: [RestrictionID]]
    private let maxKeywordWords: Int

    /// - Parameter keywords: keyword -> restrictions, normally `SeedCatalog.restrictionKeywords`.
    ///   Keywords are matched after `IngredientResolver.normalise`; empty ones are ignored.
    public init(keywords: [String: [RestrictionID]]) {
        var exact: [String: [RestrictionID]] = [:]
        var singular: [String: [RestrictionID]] = [:]
        var longest = 1
        for keyword in keywords.keys.sorted() {
            let key = IngredientResolver.normalise(keyword)
            guard !key.isEmpty, let ids = keywords[keyword], !ids.isEmpty else { continue }
            let words = key.split(separator: " ").map(String.init)
            exact[key] = SafetyTextParser.merged(exact[key] ?? [], ids)
            let singularKey = words.map { IngredientResolver.singular($0) }.joined(separator: " ")
            singular[singularKey] = SafetyTextParser.merged(singular[singularKey] ?? [], ids)
            longest = max(longest, words.count)
        }
        self.exact = exact
        self.singular = singular
        self.maxKeywordWords = longest
    }

    public func parse(_ input: String) -> [SafetyCandidate] {
        let text = TranscriptSanitiser.sanitise(input)
        let capped = text.prefix(SafetyTextParser.maxInputLength)
        var candidates: [SafetyCandidate] = []
        for clause in SafetyTextParser.clauses(capped) {
            for candidate in parseClause(clause) where !SafetyTextParser.isDuplicate(candidate, in: candidates) {
                candidates.append(candidate)
            }
        }
        if capped.endIndex != text.endIndex {
            let rest = text[capped.endIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty {
                let preview = String(rest.prefix(SafetyTextParser.overflowPreviewLength))
                let shown = preview.count < rest.count ? preview + "\u{2026}" : preview
                candidates.append(.unmapped(text: shown, memberHint: nil))
            }
        }
        return candidates
    }

    // MARK: - Clauses

    private func parseClause(_ words: [SafetyWord]) -> [SafetyCandidate] {
        guard !words.isEmpty else { return [] }
        if let hinted = memberHint(in: words) {
            let candidates = scan(hinted.content, hint: hinted.hint)
            if candidates.contains(where: { !$0.isUnmapped }) { return candidates }
        }
        let content = words.filter { $0.key != SafetyWord.colonKey }
        let candidates = scan(content, hint: nil)
        if !candidates.isEmpty { return candidates }
        let whole = SafetyTextParser.text(of: words)
        return whole.isEmpty ? [] : [.unmapped(text: whole, memberHint: nil)]
    }

    /// Keywords become restrictions, ignored words are skipped, other runs become unmapped.
    private func scan(_ words: [SafetyWord], hint: String?) -> [SafetyCandidate] {
        var candidates: [SafetyCandidate] = []
        var run: [SafetyWord] = []

        func flushRun() {
            let text = SafetyTextParser.text(of: run)
            if !text.isEmpty { candidates.append(.unmapped(text: text, memberHint: hint)) }
            run.removeAll()
        }

        var index = 0
        while index < words.count {
            if let match = keywordMatch(words, at: index) {
                flushRun()
                let matched = SafetyTextParser.text(of: Array(words[index..<(index + match.length)]))
                for id in match.ids {
                    candidates.append(.restriction(id, matchedText: matched, memberHint: hint))
                }
                index += match.length
                continue
            }
            let key = words[index].key
            if key == SafetyWord.colonKey || SafetyTextParser.ignoredWords.contains(key) {
                flushRun()
            } else {
                run.append(words[index])
            }
            index += 1
        }
        flushRun()
        return candidates
    }

    /// The longest keyword starting at `index`.
    private func keywordMatch(_ words: [SafetyWord], at index: Int) -> (ids: [RestrictionID], length: Int)? {
        let longest = min(maxKeywordWords, words.count - index)
        guard longest >= 1 else { return nil }
        for length in stride(from: longest, through: 1, by: -1) {
            let slice = words[index..<(index + length)]
            if slice.contains(where: { $0.key == SafetyWord.colonKey }) { continue }
            let phrase = slice.map(\.key).joined(separator: " ")
            if let ids = exact[phrase] { return (ids, length) }
            let singularPhrase = slice.map { IngredientResolver.singular($0.key) }.joined(separator: " ")
            if let ids = singular[singularPhrase] { return (ids, length) }
        }
        return nil
    }

    private func isKeyword(_ key: String) -> Bool {
        exact[key] != nil || singular[IngredientResolver.singular(key)] != nil
    }

    // MARK: - Member hints

    /// The clause split into a member name and the rest, when it has one of the hint shapes.
    private func memberHint(in words: [SafetyWord]) -> (hint: String, content: [SafetyWord])? {
        // "Meera: no nuts"
        if let colon = words.firstIndex(where: { $0.key == SafetyWord.colonKey }) {
            let name = Array(words[..<colon])
            if isNameLike(name) {
                return (SafetyTextParser.text(of: name), Array(words[(colon + 1)...]))
            }
            return nil
        }
        // "Meera's nut allergy"
        if let possessive = words.firstIndex(where: { $0.isPossessive }), possessive < SafetyTextParser.maxHintWords {
            let name = Array(words[...possessive])
            if isNameLike(name) {
                return (SafetyTextParser.text(of: name), Array(words[(possessive + 1)...]))
            }
        }
        // "Meera has a nut allergy", "Meera is allergic to nuts", "Meera can't have nuts"
        if let anchor = words.firstIndex(where: { SafetyTextParser.hintAnchors.contains($0.key) }),
            anchor >= 1, anchor <= SafetyTextParser.maxHintWords
        {
            let name = Array(words[..<anchor])
            if isNameLike(name) {
                return (SafetyTextParser.text(of: name), Array(words[anchor...]))
            }
        }
        // "no nuts for Meera"
        if let forIndex = words.lastIndex(where: { $0.key == "for" }), forIndex >= 1,
            words.count - forIndex - 1 >= 1, words.count - forIndex - 1 <= SafetyTextParser.maxHintWords
        {
            let name = Array(words[(forIndex + 1)...])
            if isNameLike(name) {
                return (SafetyTextParser.text(of: name), Array(words[..<forIndex]))
            }
        }
        return nil
    }

    /// One to three words that could name a person: no pronoun, grammar word or keyword.
    private func isNameLike(_ words: [SafetyWord]) -> Bool {
        guard !words.isEmpty, words.count <= SafetyTextParser.maxHintWords else { return false }
        for word in words {
            guard let first = word.key.first, first.isLetter else { return false }
            if SafetyTextParser.notNames.contains(word.key) || SafetyTextParser.hintAnchors.contains(word.key)
                || isKeyword(word.key)
            {
                return false
            }
        }
        return true
    }

    // MARK: - Words

    /// Splits text into clauses of words. Clause breaks: `, ; . ! ? ( ) [ ] / & + |`, new lines
    /// and the words in `clauseBreakWords`. A ":" is kept as its own word (a hint marker).
    static func clauses(_ text: Substring) -> [[SafetyWord]] {
        var clauseTexts: [String] = []
        var current = ""
        for character in text {
            if character.isNewline || clauseBreaks.contains(character) {
                clauseTexts.append(current)
                current = ""
            } else if character == ":" {
                current += " : "
            } else {
                current.append(character)
            }
        }
        clauseTexts.append(current)

        var clauses: [[SafetyWord]] = []
        for clauseText in clauseTexts {
            var words: [SafetyWord] = []
            for raw in clauseText.split(whereSeparator: { $0.isWhitespace }) {
                for word in SafetyWord.words(from: raw) {
                    if clauseBreakWords.contains(word.key) {
                        if !words.isEmpty { clauses.append(words) }
                        words = []
                    } else {
                        words.append(word)
                    }
                }
            }
            if !words.isEmpty { clauses.append(words) }
        }
        return clauses
    }

    static func text(of words: [SafetyWord]) -> String {
        words.filter { $0.key != SafetyWord.colonKey }.map(\.raw).joined(separator: " ")
    }

    /// One row per restriction and member hint ("no wheat/maida" is one wheat row); unmapped
    /// rows are duplicates only when identical.
    private static func isDuplicate(_ candidate: SafetyCandidate, in existing: [SafetyCandidate]) -> Bool {
        guard case .restriction(let id, _, let hint) = candidate else { return existing.contains(candidate) }
        return existing.contains { other in
            if case .restriction(let otherID, _, let otherHint) = other { return otherID == id && otherHint == hint }
            return false
        }
    }

    private static func merged(_ existing: [RestrictionID], _ more: [RestrictionID]) -> [RestrictionID] {
        var result = existing
        for id in more where !result.contains(id) { result.append(id) }
        return result
    }

    // MARK: - Vocabulary

    static let clauseBreaks: Set<Character> = [",", ";", ".", "!", "?", "(", ")", "[", "]", "/", "&", "+", "|"]
    /// Words that split clauses ("no beef and pork" is two clauses).
    public static let clauseBreakWords: Set<String> = ["and", "or", "but", "plus", "also", "nor", "then"]

    /// Words that come right after a member name: "Meera has", "Meera can't", "Meera is".
    static let hintAnchors: Set<String> = [
        "has", "have", "had", "is", "isnt", "was", "cant", "cannot", "can", "doesnt", "does", "dont", "do", "wont",
        "must", "should", "shouldnt", "avoids", "avoid", "gets", "needs", "eats", "reacts", "allergic",
    ]

    /// Words that are never a member name.
    static let notNames: Set<String> = [
        "i", "we", "he", "she", "they", "it", "you", "me", "us", "him", "her", "them", "someone", "somebody",
        "anyone", "anybody", "everyone", "everybody", "nobody", "none", "all", "both", "one", "two", "of", "the",
        "a", "an", "this", "that", "these", "those", "there", "here", "no", "not", "nothing", "some", "any",
        "please", "so", "just", "who", "its", "im", "only", "allergy", "allergies", "free", "food", "foods",
    ]

    /// Known words that carry no restriction ("no", "can't have", "allergy", "my son"). They are
    /// skipped inside a clause; a clause made only of them still comes back as `.unmapped`.
    /// None of them is a food: an unknown food word is always reported.
    public static let ignoredWords: Set<String> = [
        // negation and modals
        "no", "not", "never", "dont", "doesnt", "didnt", "cant", "cannot", "can", "could", "wont", "shouldnt",
        "mustnt", "isnt", "arent", "must", "should", "need", "needs", "nahi", "nahin", "illa", "venda",
        // verbs
        "do", "does", "did", "have", "has", "had", "having", "eat", "eats", "eating", "ate", "take", "takes",
        "is", "are", "was", "were", "be", "am", "its", "im", "get", "gets", "avoid", "avoids", "avoiding", "like",
        "likes", "want", "wants", "allowed", "cook", "use", "touch", "contain", "contains", "containing", "made",
        // allergy words
        "allergy", "allergies", "allergic", "allergen", "allergens", "intolerant", "intolerance", "intolerances",
        "sensitive", "sensitivity", "reaction", "reactions", "react", "reacts", "problem", "problems", "issue",
        "issues", "bad", "free", "severe", "mild", "strict", "strictly", "even", "trace", "traces", "any", "some",
        "kind", "kinds", "sort", "type", "types", "product", "products", "food", "foods", "item", "items",
        "stuff", "thing", "things", "anything", "too", "either", "please", "really", "very", "only",
        // grammar
        "a", "an", "the", "of", "to", "in", "on", "with", "without", "from", "at", "by", "for", "so", "just",
        "that", "this", "these", "those", "there", "here", "who", "which",
        // people
        "i", "we", "he", "she", "they", "it", "you", "me", "us", "him", "her", "them", "my", "our", "his", "their",
        "your", "one", "someone", "somebody", "anyone", "everyone", "everybody", "nobody", "all", "both", "son",
        "daughter", "husband", "wife", "kid", "kids", "child", "children", "baby", "mother", "father", "mom",
        "mum", "dad", "brother", "sister", "family", "person", "people", "member", "members", "guest", "guests",
    ]
}

/// One word of safety text.
struct SafetyWord: Sendable, Equatable {
    static let colonKey = ":"

    /// As typed (casing kept, possessive "'s" removed).
    let raw: String
    /// `IngredientResolver.normalise`d.
    let key: String
    /// Typed with a possessive "'s" ("Meera's").
    let isPossessive: Bool

    /// The words of one whitespace-free piece of text. "tree-nuts" gives two words.
    static func words(from raw: Substring) -> [SafetyWord] {
        if raw == Substring(colonKey) { return [SafetyWord(raw: ":", key: colonKey, isPossessive: false)] }
        let isWordCharacter: (Character) -> Bool = { $0.isLetter || $0.isNumber }
        guard let first = raw.firstIndex(where: isWordCharacter), let last = raw.lastIndex(where: isWordCharacter)
        else { return [] }
        var base = String(raw[first...last])
        var possessive = false
        let lower = base.lowercased()
        if lower.hasSuffix("'s") || lower.hasSuffix("\u{2019}s") {
            let stripped = String(base.dropLast(2))
            if let before = stripped.last, isWordCharacter(before) {
                base = stripped
                possessive = true
            }
        }
        let key = IngredientResolver.normalise(base)
        let pieces = key.split(separator: " ").map(String.init)
        guard !pieces.isEmpty else { return [] }
        if pieces.count == 1 {
            return [SafetyWord(raw: base, key: key, isPossessive: possessive)]
        }
        return pieces.enumerated().map { offset, piece in
            SafetyWord(raw: piece, key: piece, isPossessive: possessive && offset == pieces.count - 1)
        }
    }
}
