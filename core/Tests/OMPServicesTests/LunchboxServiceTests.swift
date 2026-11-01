import Foundation
import OMPDomain
import OMPSafetyCheck
import OMPServices
import Testing

@Suite("LunchboxService: prompt answers (U11) and school-lunch setup (AC-7.x)")
struct LunchboxServiceTests {
    @Test("the card is offered only for lunch slots in a household with children (AC-7.1)")
    func offeredForLunchWithChildren() async throws {
        let env = ServicesEnv()
        try await env.onboardWithoutRules()
        #expect(try await env.lunchbox.promptForOpenedSlot(.dinner) == nil)
        #expect(try await env.lunchbox.promptForOpenedSlot(.lunch) == .lunchbox)
        let state = try await env.repositories.promptStates.fetch(id: PromptScheduler.lunchboxPromptID)
        #expect(state?.lastShownAt == ServicesFixture.now)

        let adultsOnly = ServicesEnv()
        try await adultsOnly.households.createHousehold(adults: 2, children: 0)
        #expect(try await adultsOnly.lunchbox.promptForOpenedSlot(.lunch) == nil)
    }

    @Test("\"No\" is an answer: never asked again (U11)")
    func noIsFinal() async throws {
        let env = ServicesEnv()
        try await env.onboardWithoutRules()
        #expect(try await env.lunchbox.promptForOpenedSlot(.lunch) == .lunchbox)
        try await env.lunchbox.answerPrompt(.no)
        #expect(try await env.lunchbox.promptForOpenedSlot(.lunch) == nil)
        env.clock.advance(days: 60)
        #expect(try await env.lunchbox.promptForOpenedSlot(.lunch) == nil)
    }

    @Test("\"Yes\" is final too (U11)")
    func yesIsFinal() async throws {
        let env = ServicesEnv()
        try await env.onboardWithoutRules()
        _ = try await env.lunchbox.promptForOpenedSlot(.lunch)
        try await env.lunchbox.answerPrompt(.yes)
        env.clock.advance(days: 60)
        #expect(try await env.lunchbox.promptForOpenedSlot(.lunch) == nil)
    }

    @Test("\"Not now\" starts the 14-day cooldown (AC-7.3)")
    func notNowCoolsDown() async throws {
        let env = ServicesEnv()
        try await env.onboardWithoutRules()
        _ = try await env.lunchbox.promptForOpenedSlot(.lunch)
        try await env.lunchbox.answerPrompt(.notNow)
        #expect(try await env.lunchbox.promptForOpenedSlot(.lunch) == nil)
        env.clock.advance(days: 13)
        #expect(try await env.lunchbox.promptForOpenedSlot(.lunch) == nil)
        env.clock.advance(days: 2)
        #expect(try await env.lunchbox.promptForOpenedSlot(.lunch) == .lunchbox)
    }

    @Test("setting up school lunches gives the approved week a revision with lunchbox meals (AC-7.2, R7)")
    func setUpOnApprovedPlan() async throws {
        let env = ServicesEnv()
        let approved = try await env.approvedWeek()
        let household = try await env.household()
        let child = household.members[1].id
        let adult = household.members[0].id

        let result = try await env.lunchbox.setUpSchoolLunches(children: [child])
        #expect(result.planningRefusal == nil)
        #expect(result.household.member(child)?.needsSchoolLunch == true)
        #expect(result.household.member(child)?.schoolDays == Weekday.schoolWeek)
        #expect(result.household.member(adult)?.needsSchoolLunch == false)

        let revision = try #require(result.updatedPlans.first)
        #expect(result.updatedPlans.count == 1)
        #expect(revision.plan.basedOn == approved.id)
        #expect(revision.report.passedForEveryone)
        #expect(try await env.plans.activeApprovedPlan(series: approved.seriesId) == approved)

        let lunchboxes = revision.plan.meals.filter { $0.slot == .lunchbox }
        let schoolDates = approved.dates.filter { Weekday.schoolWeek.contains($0.weekday) }
        #expect(lunchboxes.map(\.date) == schoolDates)
        let suitable = Set(ServicesFixture.recipes.filter(\.lunchboxSuitable).map(\.id))
        for meal in lunchboxes {
            #expect(meal.recipeId.map { suitable.contains($0) } == true)
            #expect(meal.eaterIDs == [child])
            let lunch = try #require(revision.plan.meals.first { $0.date == meal.date && $0.slot == .lunch })
            #expect(lunch.eaterIDs == [adult])
        }
        // Weekend lunches are unchanged.
        for date in approved.dates where !Weekday.schoolWeek.contains(date.weekday) {
            let before = approved.meals.first { $0.date == date && $0.slot == .lunch }
            let after = revision.plan.meals.first { $0.date == date && $0.slot == .lunch }
            #expect(before == after)
        }

        // Taking the child off school lunches removes the lunchboxes again.
        let undone = try await env.lunchbox.setUpSchoolLunches(children: [])
        let reverted = try #require(undone.updatedPlans.first)
        #expect(reverted.plan.id == revision.plan.id)
        #expect(!reverted.plan.meals.contains { $0.slot == .lunchbox })
        for meal in reverted.plan.meals where meal.slot == .lunch {
            #expect(Set(meal.eaterIDs) == [adult, child])
        }
        #expect(reverted.report.passedForEveryone)
    }

    @Test("lunchboxes respect hard rules: the validator passes for the child")
    func lunchboxesRespectRules() async throws {
        let env = ServicesEnv()
        let created = try await env.households.createHousehold(adults: 1, children: 1)
        let child = created.members[1].id
        _ = try await env.safety.confirmSafetyAnswers([RuleRequest(restriction: ServicesFixture.milk, scope: .member(child))])
        let draft = try await env.plans.generateWeek()

        let result = try await env.lunchbox.setUpSchoolLunches(children: [child], days: [.monday, .wednesday])
        let updated = try #require(result.updatedPlans.first)
        #expect(updated.plan.id == draft.plan.id)
        #expect(updated.plan.meals.filter { $0.slot == .lunchbox }.map(\.date.weekday) == [.monday, .wednesday])
        let report = PlanValidator.validate(updated.plan, household: result.household, library: ServicesFixture.safetyLibrary())
        #expect(report.passedForEveryone)
    }

    @Test("with the gate refused, the household is saved but no plan changes")
    func gateRefusedLeavesPlans() async throws {
        let env = ServicesEnv()
        let approved = try await env.approvedWeek()
        let child = try await env.household().members[1].id
        let newcomer = try await env.households.addMember(role: .adult, ageBand: .adult)

        let result = try await env.lunchbox.setUpSchoolLunches(children: [child])
        #expect(result.planningRefusal == .safetyUnanswered([newcomer.id]))
        #expect(result.updatedPlans.isEmpty)
        #expect(try await env.household().member(child)?.needsSchoolLunch == true)
        #expect(try await env.repositories.mealPlans.fetchAll() == [approved])
    }

    @Test("an unknown member is refused and nothing is saved")
    func unknownMember() async throws {
        let env = ServicesEnv()
        try await env.onboardWithoutRules()
        let error = await serviceError { _ = try await env.lunchbox.setUpSchoolLunches(children: ["nobody"]) }
        #expect(error == .safetyTransition(.unknownMember("nobody")))
        #expect(try await env.household().members.allSatisfy { !$0.needsSchoolLunch })
    }
}
