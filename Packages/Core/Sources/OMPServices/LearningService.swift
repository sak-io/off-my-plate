import Foundation
import OMPDomain

/// Soft-preference learning and the reflect-back cards (AC-12.1 to AC-12.5, ADR 0013; task T19).
///
/// Soft only (AC-12.4): this service reads learning events and facts and writes facts, prompt
/// states and counters. It has no access to rules, members or safety status, and every fact it
/// can create is a `FactStatement`, which cannot express a restriction.
///
/// Events are recorded where they happen (`PlanService`: swaps, re-rolls; `PantryService`:
/// cooked; `ImportService`: staples). `refresh()` recomputes the inferred facts from them.
public final class LearningService: Sendable {
    let context: ServiceContext
    let counters: (any CounterStore)?

    /// - Parameter counters: where prompt and proposal counters go (ADR 0014); `nil` records none.
    public init(context: ServiceContext, counters: (any CounterStore)? = nil) {
        self.context = context
        self.counters = counters
    }

    // MARK: Queries

    /// Every stored fact, forgotten tombstones included.
    public func allFacts() async throws -> [Fact] {
        try await context.repositories.facts.fetchAll()
    }

    /// What the "What I've learned" screen lists (AC-12.5): active and proposed facts.
    public func learned() async throws -> [Fact] {
        try await allFacts().filter { $0.status == .active || $0.status == .proposed }
    }

    // MARK: Updating

    /// Recomputes the inferred facts from the event log (AC-12.1, AC-12.2) and stores what
    /// changed.
    @discardableResult
    public func refresh() async throws -> [Fact] {
        try await context.serialized {
            try await recompute()
        }
    }

    /// The reflect-back card to show now, if any (AC-12.2: one per week, one visible at a time,
    /// cooldowns by `PromptScheduler`). The card is recorded as shown.
    public func nextReflectBack() async throws -> Fact? {
        try await context.serialized {
            let facts = try await recompute()
            let now = context.clock.now
            let states = try await context.repositories.promptStates.fetchAll()
            let candidates = PromptCandidate.reflectBacks(from: facts)
            guard let next = PromptScheduler.next(
                candidates: candidates, states: states, now: now, timeZone: context.clock.timeZone),
                case .reflectBack(let key) = next.kind,
                let fact = facts.first(where: { $0.key == key })
            else { return nil }
            let state = states.first { $0.promptId == next.id } ?? PromptState(promptId: next.id)
            // A card still open this week stays the visible one (PromptScheduler); asking again
            // must not count it as shown a second time.
            if !Self.isOpen(state, now: now, timeZone: context.clock.timeZone) {
                try await context.repositories.promptStates.save(PromptScheduler.markShown(state, now: now))
                try await counters?.increment(CounterName.promptsShown)
            }
            return fact
        }
    }

    /// The answer to a reflect-back card (AC-12.3): Yes confirms the soft fact, Not really
    /// dismisses it, Don't ask again dismisses it for good.
    @discardableResult
    public func answerReflectBack(_ key: FactKey, _ answer: ReflectBackAnswer) async throws -> Fact? {
        try await context.serialized {
            let now = context.clock.now
            try await context.repositories.learningEvents.save(
                LearningEvent(
                    id: LearningEventID(context.makeID()), kind: .reflectBackAnswered(key: key, answer: answer),
                    at: now))
            let promptID = PromptScheduler.reflectBackPromptID(for: key)
            let state = try await context.repositories.promptStates.fetch(id: promptID)
                ?? PromptState(promptId: promptID)
            try await context.repositories.promptStates.save(
                PromptScheduler.recordReflectBack(answer, on: state, now: now))
            try await counters?.increment(CounterName.promptsAnswered)
            switch answer {
            case .yes: try await counters?.increment(CounterName.proposalsConfirmed)
            case .notReally, .dontAskAgain: try await counters?.increment(CounterName.proposalsDismissed)
            }
            let facts = try await recompute()
            return facts.first { $0.key == key }
        }
    }

    /// "Forget" (AC-12.5): the fact stops feeding scores and its earlier evidence is ignored.
    @discardableResult
    public func forget(_ id: FactID) async throws -> Fact {
        try await context.serialized {
            guard let fact = try await context.repositories.facts.fetch(id: id) else {
                throw ServiceError.factNotFound(id)
            }
            let forgotten = FactLearner.forget(fact, now: context.clock.now)
            try await context.repositories.facts.save(forgotten)
            return forgotten
        }
    }

    /// Edits a fact on the Fact sheet (U8): who it applies to, and where offered the soft
    /// statement. Saving makes it `stated` and `active`.
    @discardableResult
    public func restate(_ id: FactID, subject: FactSubject, statement: FactStatement? = nil) async throws -> [Fact] {
        try await context.serialized {
            let before = try await context.repositories.facts.fetchAll()
            guard before.contains(where: { $0.id == id }) else { throw ServiceError.factNotFound(id) }
            let after = FactLearner.restate(id, in: before, subject: subject, statement: statement, now: context.clock.now)
            try await save(changed: after, from: before)
            return after
        }
    }

    // MARK: Private

    /// Shown this ISO week and not answered or dismissed since.
    static func isOpen(_ state: PromptState, now: Date, timeZone: TimeZone) -> Bool {
        guard let shown = state.lastShownAt,
            ISOWeek(containing: shown, in: timeZone) == ISOWeek(containing: now, in: timeZone)
        else { return false }
        if let answered = state.answeredAt, answered >= shown { return false }
        if let dismissed = state.dismissedAt, dismissed >= shown { return false }
        return true
    }

    /// Runs the learner and stores changed facts. Callers hold the service lock.
    private func recompute() async throws -> [Fact] {
        let before = try await context.repositories.facts.fetchAll()
        let events = try await context.repositories.learningEvents.fetchAll()
        let after = FactLearner.update(
            facts: before, events: events, recipes: traits(), now: context.clock.now,
            timeZone: context.clock.timeZone)
        try await save(changed: after, from: before)
        return after
    }

    private func save(changed after: [Fact], from before: [Fact]) async throws {
        let known = Set(before)
        for fact in after where !known.contains(fact) {
            try await context.repositories.facts.save(fact)
        }
    }

    /// Soft traits of every library recipe: its cuisine, and ASSUMPTION: its first two
    /// non-optional ingredients as the dishes' key ingredients (seed authors list the main
    /// ingredient first). Used for preferences only, never for safety.
    private func traits() -> [RecipeID: RecipeTraits] {
        context.library.recipesByID.mapValues { recipe in
            RecipeTraits(
                cuisine: recipe.region,
                keyIngredients: Array(recipe.ingredients.filter { !$0.isOptional }.prefix(2).map(\.ingredientId)))
        }
    }
}
