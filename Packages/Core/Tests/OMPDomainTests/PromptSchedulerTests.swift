import Foundation
import OMPDomain
import Testing

/// Monday 2026-10-12 00:00 UTC; `at(n)` is day `n` at noon UTC.
private func at(_ n: Int, hour: Int = 12) -> Date {
    Date(timeIntervalSince1970: 1_791_763_200 + Double(n) * 86_400 + Double(hour) * 3_600)
}

private let utc = TimeZone(secondsFromGMT: 0)!
private let factA = FactKey(subject: .household, statement: .dislikesRecipe("upma"))
private let factB = FactKey(subject: .household, statement: .staple("rice"))
private let reflectA = PromptCandidate.reflectBack(factA)
private let reflectB = PromptCandidate.reflectBack(factB)
private let safety = PromptCandidate.safety("member-2")

private func next(_ candidates: [PromptCandidate], _ states: [PromptState] = [], now: Date) -> PromptCandidate? {
    PromptScheduler.next(candidates: candidates, states: states, now: now, timeZone: utc)
}

private func shown(_ id: PromptID, on dayNumber: Int, hour: Int = 12, answered: Bool = true) -> PromptState {
    PromptState(
        promptId: id, lastShownAt: at(dayNumber, hour: hour),
        answeredAt: answered ? at(dayNumber, hour: hour) + 60 : nil)
}

@Suite("PromptScheduler")
struct PromptSchedulerTests {
    @Test("no candidates, no card")
    func empty() {
        #expect(next([], now: at(0)) == nil)
    }

    @Test("safety comes first and is exempt from caps and cooldowns")
    func safetyFirst() {
        let capped = [
            shown("a", on: 0), shown("b", on: 0), shown("c", on: 0),
            PromptState(promptId: safety.id, lastShownAt: at(0), dismissedAt: at(0)),
        ]
        #expect(next([.lunchbox, reflectA, safety], capped, now: at(1)) == safety)
        #expect(next([.lunchbox, safety], now: at(1)) == safety)
    }

    @Test("lunchbox comes before reflect-back; reflect-backs tie-break by id")
    func ordering() {
        #expect(next([reflectA, .lunchbox], now: at(0)) == .lunchbox)
        let sorted = [reflectA, reflectB].sorted { $0.id < $1.id }
        #expect(next([reflectB, reflectA], now: at(0)) == sorted[0])
    }

    @Test("Not now cools the lunchbox prompt down for 14 days (AC-7.3)")
    func lunchboxCooldown() {
        let dismissed = PromptScheduler.record(
            .notNow, on: PromptScheduler.markShown(PromptState(promptId: PromptScheduler.lunchboxPromptID), now: at(0)),
            now: at(0))
        #expect(dismissed.dismissedAt == at(0))
        #expect(dismissed.answeredAt == nil)
        #expect(next([.lunchbox], [dismissed], now: at(13, hour: 23)) == nil)
        #expect(next([.lunchbox], [dismissed], now: at(14)) == .lunchbox)
    }

    @Test("lunchbox Yes and No are answers: never asked again (U11)", arguments: [LunchboxPromptAnswer.yes, .no])
    func lunchboxAnswered(answer: LunchboxPromptAnswer) {
        let state = PromptScheduler.record(
            answer, on: PromptState(promptId: PromptScheduler.lunchboxPromptID, lastShownAt: at(0)), now: at(0))
        #expect(state.answeredAt == at(0))
        #expect(state.dismissedAt == nil)
        #expect(next([.lunchbox], [state], now: at(1)) == nil)
        #expect(next([.lunchbox], [state], now: at(400)) == nil)
    }

    @Test("at most 3 non-safety cards per ISO week; the cap resets on Monday (AC-7.4)")
    func weeklyCap() {
        let threeThisWeek = [shown("p1", on: 0), shown("p2", on: 1), shown("p3", on: 6, hour: 23)]
        #expect(next([.lunchbox], Array(threeThisWeek.prefix(2)), now: at(6)) == .lunchbox)
        #expect(next([.lunchbox], threeThisWeek, now: at(6, hour: 23)) == nil)
        // Monday 00:30 of the next ISO week.
        #expect(next([.lunchbox], threeThisWeek, now: at(7, hour: 0) + 1_800) == .lunchbox)
    }

    @Test("safety shows do not count against the weekly cap")
    func safetyNotCounted() {
        let states = [
            shown("p1", on: 0), shown("p2", on: 0), shown(safety.id, on: 0), shown("safety:member-3", on: 1),
        ]
        #expect(next([.lunchbox], states, now: at(2)) == .lunchbox)
    }

    @Test("at most one reflect-back card per ISO week (AC-12.2)")
    func oneReflectBackPerWeek() {
        let states = [shown(reflectA.id, on: 0)]
        #expect(next([reflectB], states, now: at(2)) == nil)
        #expect(next([reflectB, .lunchbox], states, now: at(2)) == .lunchbox)
        #expect(next([reflectB], states, now: at(7)) == reflectB)
    }

    @Test("one card at a time: an open card shown this week stays the visible one")
    func openCardStays() {
        let open = shown(reflectA.id, on: 0, answered: false)
        #expect(next([.lunchbox, reflectA], [open], now: at(1)) == reflectA)
        // In a new week it is no longer "open"; normal ordering applies.
        #expect(next([.lunchbox, reflectA], [open], now: at(8)) == .lunchbox)
    }

    @Test("a reflect-back answered this week is not re-shown; a re-proposal in a later week is")
    func reflectBackReproposal() {
        let answered = PromptScheduler.record(
            .notReally, on: PromptState(promptId: reflectA.id, lastShownAt: at(0)), now: at(0, hour: 13))
        #expect(next([reflectA], [answered], now: at(3)) == nil)
        #expect(next([reflectA], [answered], now: at(15)) == reflectA)
    }

    @Test("only proposed, not suppressed facts become reflect-back candidates")
    func candidatesFromFacts() {
        func fact(_ key: FactKey, _ status: FactStatus, suppressed: Bool = false) -> Fact {
            Fact(
                id: FactLearner.stableID(for: key), subject: key.subject, statement: key.statement, origin: .inferred,
                confidence: 0.5, status: status, suppressed: suppressed, createdAt: at(0), updatedAt: at(0))
        }
        let rice = FactKey(subject: .household, statement: .staple("rice"))
        let dal = FactKey(subject: .household, statement: .favouriteRecipe("dal"))
        let candidates = PromptCandidate.reflectBacks(from: [
            fact(factA, .proposed), fact(rice, .observing), fact(dal, .proposed, suppressed: true),
        ])
        #expect(candidates == [reflectA])
        #expect(reflectA.id.rawValue.hasPrefix("reflect:"))
        #expect(safety.id == "safety:member-2")
    }
}
