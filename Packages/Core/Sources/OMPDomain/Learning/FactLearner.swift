import Foundation

/// What the learner may know about a recipe: soft attributes only (ADR 0013).
///
/// A deliberately small value type rather than `Recipe`, so the learner never sees allergen
/// tags, rules or members and cannot reason about safety.
public struct RecipeTraits: Codable, Sendable, Hashable {
    public var cuisine: CuisineID?
    /// The ingredients that characterise the dish (for example paneer in palak paneer). A
    /// swap away from the dish is evidence of a soft dislike for these.
    public var keyIngredients: [IngredientID]

    public init(cuisine: CuisineID? = nil, keyIngredients: [IngredientID] = []) {
        self.cuisine = cuisine
        self.keyIngredients = keyIngredients
    }
}

/// The learning rules of ADR 0013, as a pure function from (facts, events, now) to facts.
///
/// **Soft-only by construction (AC-12.4).** No function here takes or returns a `Rule`, a
/// `Household`, a `Member` or a safety status, and `FactStatement` has no case that can express
/// a hard restriction. However strong a pattern is, the most the learner can produce is a
/// `proposed` soft `Fact`; confirming it gives an `active` soft `Fact` (origin `confirmed`).
public enum FactLearner {
    /// Half-life of inferred evidence (G10: about 4 weeks).
    public static let halfLifeDays: Double = 28
    /// Proposal threshold (AC-12.2): at least this many independent events ...
    public static let proposalMinimumEvents = 3
    /// ... spread over at least this many different ISO weeks.
    public static let proposalMinimumWeeks = 2
    /// Decayed evidence weight at which an inferred fact's confidence reaches 1.
    public static let fullConfidenceWeight: Double = 5

    /// Evidence weight of one event: `0.5^(age / 28 days)`. Events in the future (clock skew)
    /// count as age 0.
    public static func weight(of eventDate: Date, now: Date) -> Double {
        let ageDays = max(0, now.timeIntervalSince(eventDate) / 86_400)
        return pow(0.5, ageDays / halfLifeDays)
    }

    /// Recomputes every inferred fact from the event log and applies reflect-back answers.
    ///
    /// - Parameters:
    ///   - facts: the stored facts (any origin and status).
    ///   - events: the on-device learning events (AC-12.1).
    ///   - recipes: soft traits for the recipes the events mention; unknown recipes only give
    ///     recipe-level evidence.
    ///   - now: the current instant (injected for determinism, ADR 0005).
    ///   - timeZone: used to put events into ISO weeks and to tell weekdays from weekends.
    /// - Returns: the updated facts: the input facts in their input order, then new facts
    ///   sorted by id. New facts are household-level (G10) with a key-derived id.
    public static func update(
        facts: [Fact],
        events: [LearningEvent],
        recipes: [RecipeID: RecipeTraits],
        now: Date,
        timeZone: TimeZone
    ) -> [Fact] {
        // 1. Evidence per key, de-duplicated by event id.
        var evidence: [FactKey: [LearningEvent]] = [:]
        var answers: [FactKey: [LearningEvent]] = [:]
        var seen = Set<LearningEventID>()
        for event in events {
            guard seen.insert(event.id).inserted else { continue }
            if case .reflectBackAnswered(let key, _) = event.kind {
                answers[key, default: []].append(event)
                continue
            }
            for statement in statements(for: event, recipes: recipes, timeZone: timeZone) {
                evidence[FactKey(subject: .household, statement: statement), default: []].append(event)
            }
        }

        // 2. Update existing facts, then create facts for new keys.
        var result: [Fact] = []
        var handled = Set<FactKey>()
        for fact in facts {
            handled.insert(fact.key)
            result.append(
                updated(
                    fact, evidence: evidence[fact.key] ?? [], answers: answers[fact.key] ?? [], now: now,
                    timeZone: timeZone))
        }
        let newKeys = evidence.keys.filter { !handled.contains($0) }
        var created: [Fact] = []
        for key in newKeys {
            let seed = Fact(
                id: stableID(for: key), subject: key.subject, statement: key.statement, origin: .inferred,
                confidence: 0, status: .observing, createdAt: now, updatedAt: now)
            created.append(
                updated(seed, evidence: evidence[key] ?? [], answers: answers[key] ?? [], now: now, timeZone: timeZone))
        }
        created.sort { $0.id < $1.id }
        return result + created
    }

    /// "Forget" (AC-12.5): the fact leaves the "What I've learned" list and stops feeding
    /// scores; evidence at or before `now` is ignored for this key from then on. The record is
    /// kept as a tombstone so that "Don't ask again" stays permanent.
    public static func forget(_ fact: Fact, now: Date) -> Fact {
        var copy = fact
        copy.status = .forgotten
        copy.forgottenAt = now
        copy.confidence = 0
        copy.updatedAt = now
        return copy
    }

    /// Editing a fact on the Fact sheet (U8): the user may change who it applies to; saving
    /// makes it `stated` and `active`. Only soft statements exist, so no safety-strength option
    /// can be offered.
    public static func restate(_ fact: Fact, subject: FactSubject, statement: FactStatement? = nil, now: Date)
        -> Fact
    {
        var copy = fact
        copy.subject = subject
        if let statement { copy.statement = statement }
        copy.origin = .stated
        copy.status = .active
        copy.confidence = 1
        copy.updatedAt = now
        return copy
    }

    /// The deterministic id of a learner-created fact (the same key always gives the same id).
    public static func stableID(for key: FactKey) -> FactID {
        let subject: String
        switch key.subject {
        case .household: subject = "household"
        case .member(let id): subject = "member:\(id.rawValue)"
        }
        let statement: String
        switch key.statement {
        case .cuisineAffinity(let id): statement = "cuisineAffinity:\(id.rawValue)"
        case .dislikesRecipe(let id): statement = "dislikesRecipe:\(id.rawValue)"
        case .dislikesIngredient(let id): statement = "dislikesIngredient:\(id.rawValue)"
        case .prefersQuickWeekday: statement = "prefersQuickWeekday"
        case .staple(let id): statement = "staple:\(id.rawValue)"
        case .favouriteRecipe(let id): statement = "favouriteRecipe:\(id.rawValue)"
        }
        return FactID("fact:\(subject):\(statement)")
    }

    // MARK: Signals -> statements

    /// The soft statements one event is evidence for (G10 v1 signals).
    static func statements(
        for event: LearningEvent, recipes: [RecipeID: RecipeTraits], timeZone: TimeZone
    ) -> [FactStatement] {
        var out: [FactStatement] = []
        switch event.kind {
        case .swapped(let from, let to, _):
            out.append(.dislikesRecipe(from))
            let fromTraits = recipes[from]
            let toTraits = recipes[to]
            let kept = Set(toTraits?.keyIngredients ?? [])
            for ingredient in fromTraits?.keyIngredients ?? [] where !kept.contains(ingredient) {
                out.append(.dislikesIngredient(ingredient))
            }
            if let cuisine = toTraits?.cuisine, cuisine != fromTraits?.cuisine {
                out.append(.cuisineAffinity(cuisine))
            }
        case .rerolled(let recipe, _, let reason):
            if reason == .tooLong {
                let weekday = LocalDate(event.at, in: timeZone).weekday
                if Weekday.schoolWeek.contains(weekday) { out.append(.prefersQuickWeekday) }
            } else {
                out.append(.dislikesRecipe(recipe))
            }
        case .skipped(let recipe, _):
            out.append(.dislikesRecipe(recipe))
        case .cooked(let recipe):
            out.append(.favouriteRecipe(recipe))
            if let cuisine = recipes[recipe]?.cuisine { out.append(.cuisineAffinity(cuisine)) }
        case .importedItem(let ingredient):
            out.append(.staple(ingredient))
        case .reflectBackAnswered:
            break
        }
        // One event counts at most once per statement.
        var unique: [FactStatement] = []
        for statement in out where !unique.contains(statement) { unique.append(statement) }
        return unique
    }

    // MARK: Per-fact update

    private static func updated(
        _ fact: Fact, evidence: [LearningEvent], answers: [LearningEvent], now: Date, timeZone: TimeZone
    ) -> Fact {
        var next = fact

        // "Don't ask again" is permanent, even across Forget (AC-12.3).
        let everSuppressed = fact.suppressed || answers.contains { answer(of: $0) == .dontAskAgain }
        next.suppressed = everSuppressed

        // User-owned facts are not changed by inference (until the user forgets them).
        if fact.status != .forgotten, fact.origin != .inferred {
            return stamped(next, from: fact, now: now)
        }

        // Answers given before a Forget no longer apply.
        let liveAnswers =
            answers
            .filter { isAfter($0.at, fact.forgottenAt) }
            .sorted { ($0.at, $0.id) < ($1.at, $1.id) }
        // Evidence is ignored up to the latest of: Forget, the last "Not really".
        var cutoff = fact.forgottenAt
        for event in liveAnswers where answer(of: event) == .notReally {
            cutoff = max(cutoff ?? event.at, event.at)
        }
        let latestAnswer = liveAnswers.last.flatMap { answer(of: $0) }
        let counted = evidence.filter { isAfter($0.at, cutoff) }

        let totalWeight = counted.reduce(0.0) { $0 + Self.weight(of: $1.at, now: now) }
        next.origin = .inferred
        next.confidence = min(1, totalWeight / fullConfidenceWeight)

        if fact.status == .forgotten && counted.isEmpty && liveAnswers.isEmpty {
            next.origin = fact.origin
            next.status = .forgotten
            next.confidence = 0
        } else if everSuppressed {
            next.status = .dismissed
        } else if latestAnswer == .yes {
            // Confirming keeps the fact soft (AC-12.4): it only becomes an active soft Fact.
            next.origin = .confirmed
            next.status = .active
            next.confidence = 1
        } else if meetsProposalThreshold(counted, timeZone: timeZone) {
            next.status = .proposed
        } else if latestAnswer == .notReally {
            next.status = .dismissed
        } else {
            next.status = .observing
        }
        return stamped(next, from: fact, now: now)
    }

    private static func answer(of event: LearningEvent) -> ReflectBackAnswer? {
        if case .reflectBackAnswered(_, let answer) = event.kind { return answer }
        return nil
    }

    /// `true` when there is no cutoff or `date` is strictly after it.
    private static func isAfter(_ date: Date, _ cutoff: Date?) -> Bool {
        guard let cutoff else { return true }
        return date > cutoff
    }

    /// AC-12.2: at least 3 independent events across at least 2 different ISO weeks.
    static func meetsProposalThreshold(_ events: [LearningEvent], timeZone: TimeZone) -> Bool {
        guard Set(events.map(\.id)).count >= proposalMinimumEvents else { return false }
        let weeks = Set(events.map { ISOWeek(containing: $0.at, in: timeZone) })
        return weeks.count >= proposalMinimumWeeks
    }

    private static func stamped(_ next: Fact, from old: Fact, now: Date) -> Fact {
        guard next != old else { return old }
        var copy = next
        copy.updatedAt = now
        return copy
    }
}
