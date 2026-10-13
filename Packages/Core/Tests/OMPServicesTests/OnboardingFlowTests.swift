import Foundation
import OMPDomain
import OMPRecipes
import OMPSafetyCheck
import OMPServices
import Testing

@Suite("Onboarding to approval, end to end (T18)")
struct OnboardingFlowTests {
    @Test("onboarding -> gate refuses with the reason -> answer -> validated draft -> approve")
    func endToEnd() async throws {
        let env = ServicesEnv()
        #expect(try await env.households.gateStatus() == .noHousehold)

        // AC-1.2: A + C members, all unasked.
        let created = try await env.households.createHousehold(adults: 1, children: 1)
        let ids = created.members.map(\.id)
        #expect(created.members.count == 2)
        #expect(created.members.allSatisfy { $0.safetyStatus == .unasked })
        #expect(try await env.households.gateStatus() == .refused(.safetyUnanswered(ids)))

        // AC-3.1: planning is refused, the reason names the members, and nothing is stored.
        let refusal = await serviceError { _ = try await env.plans.generateWeek() }
        #expect(refusal == .gateRefused(.safetyUnanswered(ids)))
        #expect(try await env.repositories.mealPlans.fetchAll().isEmpty)

        // AC-2.3: the child avoids peanuts; the adult is confirmed as avoiding nothing.
        let child = ids[1]
        let answered = try await env.safety.confirmSafetyAnswers([
            RuleRequest(restriction: ServicesFixture.peanut, scope: .member(child))
        ])
        #expect(answered.household.member(child)?.safetyStatus == .stated)
        #expect(answered.household.member(ids[0])?.safetyStatus == .confirmedNone)
        #expect(answered.household.rules.first?.excludedTags == [.peanut])
        #expect(try await env.households.gateStatus() == .open)

        // AC-1.4: picked cuisines become stated soft facts.
        let facts = try await env.households.recordCuisines(["southIndian", "southIndian"])
        #expect(facts.count == 1)
        #expect(facts.first?.origin == .stated)
        #expect(facts.first?.status == .active)

        // AC-1.5, AC-5.1, AC-4.2: a draft starting today, validated, without the peanut recipe.
        let draft = try await env.plans.generateWeek()
        #expect(draft.plan.status == .draft)
        #expect(draft.plan.weekStart == ServicesFixture.today)
        #expect(draft.report.passedForEveryone)
        #expect(draft.report.contentHash == draft.plan.contentHash)
        #expect(draft.plan.meals(using: ServicesFixture.peanutRecipe).isEmpty)
        #expect(draft.plan.contentVersion == "test-1")
        #expect(try await env.storedPlan(draft.plan.id) == draft.plan)
        let series = draft.plan.seriesId
        #expect(try await env.plans.workingPlan(series: series) == draft.plan)
        #expect(try await env.plans.activeApprovedPlan(series: series) == nil)
        #expect(try await env.plans.currentSeriesID() == series)

        // AC-5.2: one approval covers the whole week, with approver, time and hash.
        let outcome = try await env.plans.approve(draft.plan.id, confirmation: UserConfirmation())
        #expect(outcome.superseded == nil)
        #expect(outcome.approved.status == .approved)
        #expect(outcome.approved.approval?.approver == .thisDevice)
        #expect(outcome.approved.approval?.approvedAt == ServicesFixture.now)
        #expect(outcome.approved.approval?.contentHash == draft.plan.contentHash)
        #expect(outcome.approved.isEffectivelyApproved)
        #expect(try await env.storedPlan(draft.plan.id) == outcome.approved)
        #expect(try await env.plans.activeApprovedPlan(series: series) == outcome.approved)
        #expect(try await env.plans.hasPendingChanges(series: series) == false)
        #expect(env.diagnostics.all.isEmpty)
    }

    @Test("the bundled seed plans, validates and approves a peanut-free week")
    func bundledSeed() async throws {
        let seed = try SeedLoader.loadBundled()
        let env = ServicesEnv(library: PlanningLibrary(seed: seed))
        try await env.households.createHousehold(adults: 2, children: 1)
        let answered = try await env.safety.confirmSafetyAnswers([RuleRequest(restriction: "peanuts", scope: .household)])
        #expect(answered.household.rules.first?.excludedTags.contains(.peanut) == true)

        let draft = try await env.plans.generateWeek()
        #expect(draft.report.passedForEveryone)
        #expect(draft.plan.contentVersion == seed.contentVersion)
        #expect(draft.plan.meals.contains { $0.recipeId != nil })
        let outcome = try await env.plans.approve(draft.plan.id, confirmation: UserConfirmation())
        #expect(outcome.approved.isEffectivelyApproved)
        #expect(env.diagnostics.all.isEmpty)
    }

    @Test("gate refusal for a re-confirmation that fell due surfaces that reason (G3)")
    func reconfirmationDue() async throws {
        let env = ServicesEnv()
        let household = try await env.onboardWithoutRules()
        env.clock.advance(days: SafetyGate.reconfirmationPeriodDays + 1)

        let refusal = await serviceError { _ = try await env.plans.generateWeek() }
        #expect(refusal == .gateRefused(.reconfirmationDue(household.activeMembers.map(\.id))))

        // "Still correct?" refreshes the answers and planning works again.
        _ = try await env.safety.reconfirm()
        #expect(try await env.households.gateStatus() == .open)
        _ = try await env.plans.generateWeek()
    }

    @Test("onboarding validates the size and runs once")
    func onboardingErrors() async throws {
        let env = ServicesEnv()
        let tooFew = await serviceError { _ = try await env.households.createHousehold(adults: 0, children: 0) }
        #expect(tooFew == .householdSize(.tooFew(total: 0)))
        try await env.households.createHousehold(adults: 2, children: 0)
        let twice = await serviceError { _ = try await env.households.createHousehold(adults: 1, children: 0) }
        #expect(twice == .householdAlreadyExists)
    }

    @Test("skipping the cuisine step stores nothing (AC-1.4)")
    func skipCuisines() async throws {
        let env = ServicesEnv()
        try await env.households.createHousehold(adults: 1, children: 0)
        #expect(try await env.households.recordCuisines([]).isEmpty)
        #expect(try await env.repositories.facts.fetchAll().isEmpty)
    }

    @Test("adding a person blocks planning but keeps the approved plan usable (AC-3.2, AC-3.3)")
    func addedMemberBlocksPlanning() async throws {
        let env = ServicesEnv()
        let approved = try await env.approvedWeek()

        let member = try await env.households.addMember(role: .adult, ageBand: .adult)
        #expect(member.safetyStatus == .unasked)
        #expect(try await env.households.gateStatus() == .refused(.safetyUnanswered([member.id])))
        #expect(try await env.plans.activeApprovedPlan(series: approved.seriesId) == approved)

        let regenerate = await serviceError { _ = try await env.plans.regenerate(approved.id) }
        #expect(regenerate == .gateRefused(.safetyUnanswered([member.id])))
        let meal = try #require(approved.meals.first)
        let reroll = await serviceError { _ = try await env.plans.reroll(meal.id, in: approved.id, reason: nil) }
        #expect(reroll == .gateRefused(.safetyUnanswered([member.id])))
        let lock = await serviceError { _ = try await env.plans.setLocked(true, meal: meal.id, in: approved.id) }
        #expect(lock == .gateRefused(.safetyUnanswered([member.id])))
        #expect(try await env.plans.hasPendingChanges(series: approved.seriesId) == false)

        // Answering for the new member opens the gate again.
        _ = try await env.safety.confirmMemberAnswer(for: member.id)
        #expect(try await env.households.gateStatus() == .open)
        _ = try await env.plans.regenerate(approved.id)
        #expect(try await env.plans.hasPendingChanges(series: approved.seriesId))
    }

    @Test("removing and re-banding members goes through the safety transitions (AC-3.4)")
    func memberChanges() async throws {
        let env = ServicesEnv()
        let household = try await env.onboardWithoutRules()
        let child = household.members[1].id

        #expect(try await env.households.setAgeBand(.adult, for: child))
        #expect(try await env.households.gateStatus() == .refused(.safetyUnanswered([child])))

        let removed = try await env.households.removeMember(child)
        #expect(removed.member(child)?.isDeleted == true)
        #expect(try await env.households.gateStatus() == .open)

        let last = await serviceError { _ = try await env.households.removeMember(household.members[0].id) }
        #expect(last == .safetyTransition(.lastMember(household.members[0].id)))
    }

    @Test("approval is refused while anyone is unasked (U4)")
    func approvalRefusedWhileUnasked() async throws {
        let env = ServicesEnv()
        try await env.onboardWithoutRules()
        let draft = try await env.plans.generateWeek()
        let member = try await env.households.addMember(role: .child, ageBand: .child)

        let refusal = await serviceError {
            _ = try await env.plans.approve(draft.plan.id, confirmation: UserConfirmation())
        }
        #expect(refusal == .gateRefused(.safetyUnanswered([member.id])))
        #expect(try await env.storedPlan(draft.plan.id).status == .draft)
    }

    @Test("a second first draft is refused until the open one is approved or discarded")
    func openDraftBlocksNewWeek() async throws {
        let env = ServicesEnv()
        try await env.onboardWithoutRules()
        let first = try await env.plans.generateWeek()
        let again = await serviceError { _ = try await env.plans.generateWeek() }
        #expect(again == .openDraftExists(first.plan.id))

        let discarded = try await env.plans.discard(first.plan.id)
        #expect(discarded.status == .discarded)
        let approveDiscarded = await serviceError {
            _ = try await env.plans.approve(first.plan.id, confirmation: UserConfirmation())
        }
        #expect(approveDiscarded == .lifecycle(.wrongStatus(expected: .draft, actual: .discarded)))

        // R8: after an approved week, the next one starts the day after it ends.
        let second = try await env.plans.generateWeek()
        _ = try await env.plans.approve(second.plan.id, confirmation: UserConfirmation())
        let next = try await env.plans.generateWeek()
        #expect(next.plan.weekStart == second.plan.endDate.adding(days: 1))
        #expect(next.plan.seriesId != second.plan.seriesId)
    }
}
