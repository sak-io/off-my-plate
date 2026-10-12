import Foundation
import OMPDomain
import Testing

/// Monday 2026-10-12 00:00 UTC; day `n` at noon UTC.
private let mondayMidnight: Double = 1_791_763_200
private func day(_ n: Int, hour: Int = 12) -> Date {
    Date(timeIntervalSince1970: mondayMidnight + Double(n) * 86_400 + Double(hour) * 3_600)
}

private let utc = TimeZone(secondsFromGMT: 0)!
private let paneerDish: RecipeID = "palak-paneer"
private let otherDish: RecipeID = "aloo-gobi"
private let paneer: IngredientID = "paneer"
private let recipes: [RecipeID: RecipeTraits] = [
    paneerDish: RecipeTraits(cuisine: "northIndian", keyIngredients: [paneer, "spinach"]),
    otherDish: RecipeTraits(cuisine: "northIndian", keyIngredients: ["potato", "cauliflower", "spinach"]),
]
private let dislikeKey = FactKey(subject: .household, statement: .dislikesIngredient(paneer))

private func skipEvent(_ index: Int, on dayNumber: Int, hour: Int = 12) -> LearningEvent {
    LearningEvent(
        id: LearningEventID("skip-\(index)"), kind: .skipped(recipe: "upma", slot: .breakfast),
        at: day(dayNumber, hour: hour))
}

private func answer(_ answer: ReflectBackAnswer, key: FactKey, on dayNumber: Int, id: String) -> LearningEvent {
    LearningEvent(id: LearningEventID(id), kind: .reflectBackAnswered(key: key, answer: answer), at: day(dayNumber))
}

private func learn(_ facts: [Fact], _ events: [LearningEvent], now: Date) -> [Fact] {
    FactLearner.update(facts: facts, events: events, recipes: recipes, now: now, timeZone: utc)
}

private func learn(_ events: [LearningEvent], now: Date) -> [Fact] {
    learn([], events, now: now)
}

private let upmaKey = FactKey(subject: .household, statement: .dislikesRecipe("upma"))
private func upmaFact(_ facts: [Fact]) -> Fact? {
    facts.first { $0.key == upmaKey }
}

@Suite("FactLearner")
struct FactLearnerTests {
    // MARK: Threshold (AC-12.2)

    @Test("2 events across 2 weeks stay observing; 3 events across 2 weeks are proposed")
    func eventCountBoundary() throws {
        let two = try #require(upmaFact(learn([skipEvent(1, on: 0), skipEvent(2, on: 7)], now: day(8))))
        #expect(two.status == .observing)
        #expect(two.origin == .inferred)

        let three = try #require(upmaFact(learn([skipEvent(1, on: 0), skipEvent(2, on: 1), skipEvent(3, on: 7)], now: day(8))))
        #expect(three.status == .proposed)
        #expect(three.origin == .inferred)
    }

    @Test("3 events in 1 ISO week stay observing; across 2 weeks they are proposed")
    func weekCountBoundary() throws {
        // Monday, Wednesday, Sunday of the same ISO week.
        let oneWeek = try #require(upmaFact(learn([skipEvent(1, on: 0), skipEvent(2, on: 2), skipEvent(3, on: 6)], now: day(7))))
        #expect(oneWeek.status == .observing)
        // Sunday 23:00 and Monday 01:00 are in different ISO weeks.
        let twoWeeks = try #require(
            upmaFact(
                learn([skipEvent(1, on: 0), skipEvent(2, on: 6, hour: 23), skipEvent(3, on: 7, hour: 1)], now: day(7))))
        #expect(twoWeeks.status == .proposed)
    }

    @Test("an event id is counted once")
    func duplicateEventsCountOnce() throws {
        let fact = try #require(upmaFact(learn([skipEvent(1, on: 0), skipEvent(1, on: 0), skipEvent(2, on: 7)], now: day(8))))
        #expect(fact.status == .observing)
    }

    // MARK: Decay (G10)

    @Test("evidence weight halves every 28 days and future events count as now")
    func decay() {
        let now = day(56)
        #expect(abs(FactLearner.weight(of: now, now: now) - 1) < 1e-9)
        #expect(abs(FactLearner.weight(of: day(28), now: now) - 0.5) < 1e-9)
        #expect(abs(FactLearner.weight(of: day(0), now: now) - 0.25) < 1e-9)
        #expect(abs(FactLearner.weight(of: day(60), now: now) - 1) < 1e-9)
    }

    @Test("confidence of an inferred fact decays without reinforcement")
    func confidenceDecays() throws {
        let events = [skipEvent(1, on: 0), skipEvent(2, on: 1), skipEvent(3, on: 7)]
        let fresh = try #require(upmaFact(learn(events, now: day(7))))
        let later = try #require(upmaFact(learn([fresh], events, now: day(63))))
        // Weights at day 7: 0.5^(7/28) + 0.5^(6/28) + 1 ~ 2.70; confidence = weight / 5.
        let expected = (pow(0.5, 7.0 / 28) + pow(0.5, 6.0 / 28) + 1) / FactLearner.fullConfidenceWeight
        #expect(abs(fresh.confidence - expected) < 1e-9)
        #expect(abs(later.confidence - fresh.confidence / 4) < 1e-9)
        #expect(later.confidence < fresh.confidence)
    }

    @Test("the same input gives the same output (pure and deterministic)")
    func deterministic() {
        let events = [skipEvent(1, on: 0), skipEvent(2, on: 1), skipEvent(3, on: 7)]
        let first = learn(events, now: day(9))
        #expect(first == learn(events, now: day(9)))
        #expect(learn(first, events, now: day(9)) == first)
        #expect(first.allSatisfy { $0.id == FactLearner.stableID(for: $0.key) })
    }

    // MARK: Answers (AC-12.3)

    @Test("Yes confirms the fact and keeps it soft")
    func yesConfirms() throws {
        let events = [skipEvent(1, on: 0), skipEvent(2, on: 1), skipEvent(3, on: 7)]
        let proposed = learn(events, now: day(8))
        let confirmed = try #require(
            upmaFact(learn(proposed, events + [answer(.yes, key: upmaKey, on: 8, id: "a1")], now: day(9))))
        #expect(confirmed.status == .active)
        #expect(confirmed.origin == .confirmed)
        #expect(confirmed.confidence == 1)
        #expect(confirmed.statement == .dislikesRecipe("upma"))
    }

    @Test("Not really dismisses; only fresh evidence (3 events, 2 weeks) can propose it again")
    func notReallyNeedsFreshEvidence() throws {
        let events = [skipEvent(1, on: 0), skipEvent(2, on: 1), skipEvent(3, on: 7)]
        let proposed = learn(events, now: day(8))
        let withAnswer = events + [answer(.notReally, key: upmaKey, on: 8, id: "a1")]
        let dismissed = learn(proposed, withAnswer, now: day(9))
        #expect(upmaFact(dismissed)?.status == .dismissed)

        let twoMore = withAnswer + [skipEvent(4, on: 9), skipEvent(5, on: 15)]
        #expect(upmaFact(learn(dismissed, twoMore, now: day(16)))?.status == .dismissed)

        let threeMore = twoMore + [skipEvent(6, on: 16)]
        #expect(upmaFact(learn(dismissed, threeMore, now: day(17)))?.status == .proposed)
    }

    @Test("Don't ask again is never re-proposed, however much evidence follows, even after Forget")
    func dontAskAgainIsPermanent() throws {
        var events = [skipEvent(1, on: 0), skipEvent(2, on: 1), skipEvent(3, on: 7)]
        var facts = learn(events, now: day(8))
        events.append(answer(.dontAskAgain, key: upmaKey, on: 8, id: "a1"))
        facts = learn(facts, events, now: day(9))
        #expect(upmaFact(facts)?.status == .dismissed)
        #expect(upmaFact(facts)?.suppressed == true)

        for index in 10..<40 { events.append(skipEvent(index, on: index * 3)) }
        facts = learn(facts, events, now: day(130))
        let after = try #require(upmaFact(facts))
        #expect(after.status == .dismissed)
        #expect(after.suppressed)
        #expect(PromptCandidate.reflectBacks(from: facts).isEmpty)

        // Forget, then more evidence: still never proposed.
        facts = facts.map { $0.key == upmaKey ? FactLearner.forget($0, now: day(131)) : $0 }
        for index in 40..<50 { events.append(skipEvent(index, on: 132 + index)) }
        let afterForget = try #require(upmaFact(learn(facts, events, now: day(200))))
        #expect(afterForget.suppressed)
        #expect(afterForget.status != .proposed)
    }

    // MARK: Forget (AC-12.5)

    @Test("Forget ignores older evidence; new evidence starts from zero")
    func forgetIgnoresOlderEvidence() throws {
        let events = [skipEvent(1, on: 0), skipEvent(2, on: 1), skipEvent(3, on: 7), skipEvent(4, on: 8)]
        let proposed = learn(events, now: day(9))
        let forgotten = proposed.map { FactLearner.forget($0, now: day(9)) }
        let stillForgotten = try #require(upmaFact(learn(forgotten, events, now: day(10))))
        #expect(stillForgotten.status == .forgotten)
        #expect(stillForgotten.confidence == 0)
        #expect(stillForgotten.forgottenAt == day(9))

        // 6 events in total, but only 2 after Forget: observing, with only their weight.
        let more = events + [skipEvent(5, on: 10), skipEvent(6, on: 14)]
        let revived = try #require(upmaFact(learn(forgotten, more, now: day(14))))
        #expect(revived.status == .observing)
        let expected = (FactLearner.weight(of: day(10), now: day(14)) + 1) / FactLearner.fullConfidenceWeight
        #expect(abs(revived.confidence - expected) < 1e-9)
    }

    @Test("a forgotten confirmed fact loses its old Yes")
    func forgetDropsOldAnswers() throws {
        let events = [skipEvent(1, on: 0), skipEvent(2, on: 1), skipEvent(3, on: 7), answer(.yes, key: upmaKey, on: 8, id: "a1")]
        let confirmed = learn(events, now: day(8))
        #expect(upmaFact(confirmed)?.status == .active)
        let forgotten = confirmed.map { FactLearner.forget($0, now: day(9)) }
        #expect(upmaFact(learn(forgotten, events, now: day(10)))?.status == .forgotten)
    }

    // MARK: User-owned facts

    @Test("stated facts are not changed by inference; restating makes a fact stated (U8)")
    func statedFactsAreUserOwned() throws {
        let stated = Fact(
            id: "fact-1", statement: .dislikesRecipe("upma"), origin: .stated, confidence: 1, status: .active,
            createdAt: day(0), updatedAt: day(0))
        let events = [skipEvent(1, on: 0), skipEvent(2, on: 1), skipEvent(3, on: 7), answer(.notReally, key: upmaKey, on: 8, id: "a")]
        #expect(learn([stated], events, now: day(9)) == [stated])

        let inferred = try #require(upmaFact(learn([skipEvent(1, on: 0)], now: day(1))))
        let restated = FactLearner.restate(inferred, subject: .member("child-1"), now: day(2))
        #expect(restated.origin == .stated)
        #expect(restated.status == .active)
        #expect(restated.subject == .member("child-1"))
        #expect(restated.id == inferred.id)
    }

    // MARK: Signals (AC-12.1)

    @Test("signals map to soft statements")
    func signalsMapToStatements() {
        let events = [
            LearningEvent(id: "e1", kind: .swapped(from: paneerDish, to: otherDish, slot: .dinner), at: day(0)),
            LearningEvent(id: "e2", kind: .cooked(recipe: otherDish), at: day(0)),
            LearningEvent(id: "e3", kind: .importedItem(ingredient: "rice"), at: day(0)),
            // Monday: counts as a weekday "too long".
            LearningEvent(id: "e4", kind: .rerolled(recipe: "biryani", slot: .dinner, reason: .tooLong), at: day(0)),
            LearningEvent(id: "e5", kind: .rerolled(recipe: "upma", slot: .breakfast, reason: .kidsWontEatIt), at: day(0)),
        ]
        let statements = Set(learn(events, now: day(1)).map(\.statement))
        #expect(
            statements == [
                .dislikesRecipe(paneerDish), .dislikesIngredient(paneer), .favouriteRecipe(otherDish),
                .cuisineAffinity("northIndian"), .staple("rice"), .prefersQuickWeekday, .dislikesRecipe("upma"),
            ])
        // "spinach" is in both dishes, so swapping is no evidence against it; same cuisine is
        // no swap evidence for a cuisine (the affinity above comes from "cooked").
        #expect(!statements.contains(.dislikesIngredient("spinach")))
    }

    @Test("a 'too long' re-roll on a weekend is not weekday evidence")
    func tooLongOnWeekend() {
        let saturday = LearningEvent(
            id: "e1", kind: .rerolled(recipe: "biryani", slot: .dinner, reason: .tooLong), at: day(5))
        #expect(learn([saturday], now: day(6)).isEmpty)
    }

    // MARK: Soft-only by construction (AC-12.4, ADR 0013)

    @Test("the learner's signature only takes and returns soft facts (compile-level pin)")
    func signatureCannotTouchRules() {
        // If anyone adds a Rule, Household or Member parameter, or changes the return type,
        // this line stops compiling.
        let update: ([Fact], [LearningEvent], [RecipeID: RecipeTraits], Date, TimeZone) -> [Fact] =
            FactLearner.update(facts:events:recipes:now:timeZone:)
        let forget: (Fact, Date) -> Fact = FactLearner.forget(_:now:)
        #expect(update([], [], [:], day(0), utc).isEmpty)
        #expect(forget(FactLearner.restate(stated(), subject: .household, now: day(0)), day(1)).status == .forgotten)
    }

    @Test("FactStatement has only the six soft cases (exhaustive switch, no hard case)")
    func statementsAreSoft() {
        // A new case breaks this exhaustive switch, forcing a review against ADR 0013.
        func isSoft(_ statement: FactStatement) -> Bool {
            switch statement {
            case .cuisineAffinity, .dislikesRecipe, .dislikesIngredient, .prefersQuickWeekday, .staple,
                .favouriteRecipe:
                return true
            }
        }
        #expect(isSoft(.dislikesIngredient(paneer)))
    }

    @Test("100 dairy swaps produce only a soft proposed Fact; confirming it keeps it soft")
    func hundredDairySwaps() throws {
        var events: [LearningEvent] = []
        for index in 0..<100 {
            events.append(
                LearningEvent(
                    id: LearningEventID("swap-\(index)"),
                    kind: .swapped(from: paneerDish, to: otherDish, slot: .dinner), at: day(index / 2)))
        }
        let facts = learn(events, now: day(50))
        #expect(Set(facts.map(\.statement)) == [.dislikesRecipe(paneerDish), .dislikesIngredient(paneer)])
        for fact in facts {
            #expect(fact.origin == .inferred)
            #expect(fact.status == .proposed)
            #expect(fact.subject == .household)
            #expect(fact.confidence <= 1)
        }

        let confirmed = learn(facts, events + [answer(.yes, key: dislikeKey, on: 50, id: "yes")], now: day(51))
        let dairy = try #require(confirmed.first { $0.key == dislikeKey })
        #expect(dairy.status == .active)
        #expect(dairy.origin == .confirmed)
        #expect(dairy.statement == .dislikesIngredient(paneer))
    }

    private func stated() -> Fact {
        Fact(
            id: "fact-x", statement: .staple("rice"), origin: .stated, confidence: 1, status: .active,
            createdAt: day(0), updatedAt: day(0))
    }
}
