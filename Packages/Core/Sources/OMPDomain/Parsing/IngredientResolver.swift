import Foundation

/// Finds taxonomy ingredients for free text: the pantry search picker (AC-9.1), Notes import rows
/// (AC-11.1) and voice input (T16). Plan section 8.
///
/// Matching is on normalised text (`IngredientResolver.normalise`) against each ingredient's name
/// and synonyms, which include Hindi, Tamil and Malayalam names ("kappa", "chemmeen", "velichenna").
/// The result is a ranked candidate list, never a forced match; `confidentMatch` only answers when
/// exactly one ingredient matches at the best, exact-or-plural tier.
///
/// The ranking is deterministic and independent of the order of `ingredients`: by `MatchKind`,
/// then by how close the matched term's length is to the query's, then by name, then by id.
public struct IngredientResolver: Sendable {
    /// How a candidate matched, best first.
    public enum MatchKind: Int, Sendable, Hashable, Comparable, CaseIterable {
        /// The query is the ingredient's name ("rice").
        case exactName
        /// The query is one of its synonyms ("chawal", "kappa").
        case exactSynonym
        /// Equal after removing plurals ("onions", "green chillies").
        case singularised
        /// The name or a synonym starts with the query ("chem" -> "chemmeen"), for type-ahead.
        case prefix
        /// Every word of the name or synonym is in the query, or the reverse
        /// ("fresh curry leaves" -> curry leaves).
        case token
        /// The name or a synonym contains the query (at least 3 characters).
        case contains
        /// One edit away, for words of at least 5 letters ("tomatoe", "kariveppilla").
        case nearMiss

        public static func < (lhs: MatchKind, rhs: MatchKind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// One ranked match.
    public struct Candidate: Sendable, Hashable {
        public let ingredientId: IngredientID
        /// The ingredient's display name.
        public let name: String
        /// The name or synonym that matched, as written in the taxonomy.
        public let matchedTerm: String
        public let kind: MatchKind

        public init(ingredientId: IngredientID, name: String, matchedTerm: String, kind: MatchKind) {
            self.ingredientId = ingredientId
            self.name = name
            self.matchedTerm = matchedTerm
            self.kind = kind
        }
    }

    /// Queries are cut to this many characters before matching (untrusted input).
    public static let maxQueryLength = 100
    /// Shortest query for a `contains` match.
    static let minContainsLength = 3
    /// Shortest query and term for a `nearMiss` match.
    static let minNearMissLength = 5

    private struct Term: Sendable {
        let text: String
        let key: String
        let keyCharacters: [Character]
        let singularKey: String
        let singularWords: Set<String>
        let isName: Bool
    }

    private struct Entry: Sendable {
        let id: IngredientID
        let name: String
        let nameKey: String
        let terms: [Term]
    }

    private let entries: [Entry]

    /// Builds the index. When two ingredients share an id, the first one is used.
    public init(ingredients: [Ingredient]) {
        var seen = Set<IngredientID>()
        var entries: [Entry] = []
        for ingredient in ingredients where seen.insert(ingredient.id).inserted {
            var terms: [Term] = []
            for (offset, text) in ([ingredient.name] + ingredient.synonyms).enumerated() {
                let key = IngredientResolver.normalise(text)
                guard !key.isEmpty else { continue }
                let words = key.split(separator: " ").map { IngredientResolver.singular(String($0)) }
                terms.append(
                    Term(
                        text: text, key: key, keyCharacters: Array(key), singularKey: words.joined(separator: " "),
                        singularWords: Set(words), isName: offset == 0))
            }
            entries.append(
                Entry(
                    id: ingredient.id, name: ingredient.name, nameKey: IngredientResolver.normalise(ingredient.name),
                    terms: terms))
        }
        self.entries = entries
    }

    /// Ranked candidates for `query`, at most `limit`. Empty for a blank query.
    public func candidates(for query: String, limit: Int = 10) -> [Candidate] {
        let key = IngredientResolver.normalise(String(query.prefix(IngredientResolver.maxQueryLength)))
        guard !key.isEmpty, limit > 0 else { return [] }
        let keyCharacters = Array(key)
        let words = key.split(separator: " ").map { IngredientResolver.singular(String($0)) }
        let probe = Query(
            key: key, characters: keyCharacters, singularKey: words.joined(separator: " "), words: Set(words))

        var ranked: [(candidate: Candidate, lengthGap: Int, nameKey: String)] = []
        for entry in entries {
            var best: (kind: MatchKind, gap: Int, term: Term)?
            for term in entry.terms {
                guard let kind = IngredientResolver.match(probe, term) else { continue }
                let gap = abs(term.keyCharacters.count - keyCharacters.count)
                if let current = best,
                    (current.kind, current.gap, current.term.key) <= (kind, gap, term.key)
                {
                    continue
                }
                best = (kind, gap, term)
            }
            if let best {
                let candidate = Candidate(
                    ingredientId: entry.id, name: entry.name, matchedTerm: best.term.text, kind: best.kind)
                ranked.append((candidate, best.gap, entry.nameKey))
            }
        }
        ranked.sort { lhs, rhs in
            if lhs.candidate.kind != rhs.candidate.kind { return lhs.candidate.kind < rhs.candidate.kind }
            if lhs.lengthGap != rhs.lengthGap { return lhs.lengthGap < rhs.lengthGap }
            if lhs.nameKey != rhs.nameKey { return lhs.nameKey < rhs.nameKey }
            return lhs.candidate.ingredientId < rhs.candidate.ingredientId
        }
        return ranked.prefix(limit).map { $0.candidate }
    }

    /// The single ingredient `query` names, or nil when there is none or more than one: the best
    /// candidate must be an exact name, exact synonym or plural match, and no other ingredient may
    /// match at that same tier. Callers still show the row for review (AC-11.2).
    public func confidentMatch(for query: String) -> Candidate? {
        let top = candidates(for: query, limit: 2)
        guard let first = top.first, first.kind <= .singularised else { return nil }
        if top.count > 1, top[1].kind == first.kind { return nil }
        return first
    }

    // MARK: - Matching

    private struct Query {
        let key: String
        let characters: [Character]
        let singularKey: String
        let words: Set<String>
    }

    private static func match(_ query: Query, _ term: Term) -> MatchKind? {
        if query.key == term.key { return term.isName ? .exactName : .exactSynonym }
        if query.singularKey == term.singularKey { return .singularised }
        if term.key.hasPrefix(query.key) { return .prefix }
        if term.singularWords.isSubset(of: query.words) || query.words.isSubset(of: term.singularWords) {
            return .token
        }
        if query.characters.count >= minContainsLength, term.key.contains(query.key) { return .contains }
        if query.characters.count >= minNearMissLength, term.keyCharacters.count >= minNearMissLength,
            isAtMostOneEditApart(query.characters, term.keyCharacters)
        {
            return .nearMiss
        }
        return nil
    }

    /// True when `a` and `b` differ by at most one insertion, deletion or substitution.
    static func isAtMostOneEditApart(_ a: [Character], _ b: [Character]) -> Bool {
        let (short, long) = a.count <= b.count ? (a, b) : (b, a)
        guard long.count - short.count <= 1 else { return false }
        var i = 0
        var j = 0
        var edits = 0
        while i < short.count, j < long.count {
            if short[i] == long[j] {
                i += 1
                j += 1
                continue
            }
            edits += 1
            if edits > 1 { return false }
            if short.count == long.count { i += 1 }
            j += 1
        }
        return edits + (long.count - j) + (short.count - i) <= 1
    }

    // MARK: - Normalisation

    /// Lowercased (locale-independent `lowercased()`), apostrophes removed, every other character
    /// that is not a letter or number turned into a space, spaces collapsed and trimmed.
    /// Combining marks inside a letter (Malayalam and Devanagari vowel signs) are kept.
    public static func normalise(_ text: String) -> String {
        var result = ""
        var pendingSpace = false
        for character in text.lowercased() {
            if character == "'" || character == "\u{2019}" || character == "`" { continue }
            if character.isLetter || character.isNumber {
                if pendingSpace, !result.isEmpty { result.append(" ") }
                pendingSpace = false
                result.append(character)
            } else {
                pendingSpace = true
            }
        }
        return result
    }

    /// A simple English singular for one lowercased word: "tomatoes" -> "tomato", "chillies" ->
    /// "chilli", "curries" -> "curry", "peaches" -> "peach", "onions" -> "onion". Applied to both
    /// queries and terms, so it only has to be consistent, not perfect.
    static func singular(_ word: String) -> String {
        let count = word.count
        if count > 6, word.hasSuffix("illies") { return String(word.dropLast(2)) }
        if count > 4, word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if count > 4, word.hasSuffix("oes") { return String(word.dropLast(2)) }
        if count > 4,
            word.hasSuffix("ches") || word.hasSuffix("shes") || word.hasSuffix("sses") || word.hasSuffix("xes")
        {
            return String(word.dropLast(2))
        }
        if count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast()) }
        return word
    }
}
