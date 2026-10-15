import Foundation
import OMPDomain
import OMPSafetyCheck
@testable import OMPServices
import Testing

@Suite("PlanService: edits, revisions and learning events (T18)")
struct PlanServiceTests {
    @Test("editing an approved plan creates a draft revision with a diff; the approved plan stays active (AC-5.4, A6)")
    func editApprovedCreatesRevision() async throws {
        let env = ServicesEnv()
        let approved = try await env.approvedWeek()
        let meal = try #require(approved.meals.first { $0.slot == .dinner })

        let revision = try await env.plans.reroll(meal.id, in: approved.id, reason: .tooLong)
        #expect(revision.plan.status == .draft)
        #expect(revision.plan.revision == approved.revision + 1)
        #expect(revision.plan.basedOn == approved.id)
        #expect(revision.plan.seriesId == approved.seriesId)
        #expect(revision.report.passedForEveryone)
        #expect(revision.plan.meal(meal.id)?.recipeId != meal.recipeId)

        // A6: the approved plan is untouched and still what the list and Mark cooked read.
        #expect(try await env.storedPlan(approved.id) == approved)
        #expect(try await env.plans.activeApprovedPlan(series: approved.seriesId) == approved)
        #expect(try await env.plans.workingPlan(series: approved.seriesId) == revision.plan)
        #expect(try await env.plans.hasPendingChanges(series: approved.seriesId))
        let pending = try await env.plans.pendingDiff(series: approved.seriesId)
        let diff = try #require(pending)
        #expect(diff.listedChanges.count == 1)
        #expect(diff.listedChanges.first?.was?.id == meal.id)

        // Edits go to the working plan only: the approved id is stale now.
        let stale = await serviceError { _ = try await env.plans.reroll(meal.id, in: approved.id, reason: nil) }
        #expect(stale == .notWorkingPlan(approved.id))

        // A second edit changes the same draft revision in place.
        let other = try #require(approved.meals.first { $0.slot == .lunch })
        let again = try await env.plans.reroll(other.id, in: revision.plan.id, reason: nil)
        #expect(again.plan.id == revision.plan.id)
        #expect(try await env.repositories.mealPlans.fetchSeries(approved.seriesId).count == 2)

        // AC-5.7: approving the revision supersedes the old plan atomically.
        let outcome = try await env.plans.approve(revision.plan.id, confirmation: UserConfirmation())
        #expect(outcome.superseded?.status == .superseded)
        #expect(try await env.storedPlan(approved.id).status == .superseded)
        #expect(try await env.plans.activeApprovedPlan(series: approved.seriesId)?.id == revision.plan.id)
        #expect(try await env.plans.hasPendingChanges(series: approved.seriesId) == false)
    }

    @Test("swap and re-roll are logged as learning events (AC-8.2, AC-12.1)")
    func learningEvents() async throws {
        let env = ServicesEnv()
        try await env.onboardWithoutRules()
        let draft = try await env.plans.generateWeek()
        let breakfast = try #require(draft.plan.meals.first { $0.slot == .breakfast })
        let dinner = try #require(draft.plan.meals.first { $0.slot == .dinner })
        let oldBreakfast = try #require(breakfast.recipeId)
        let oldDinner = try #require(dinner.recipeId)

        let rerolled = try await env.plans.reroll(dinner.id, in: draft.plan.id, reason: .kidsWontEatIt)
        #expect(rerolled.plan.id == draft.plan.id)

        let offered = try await env.plans.alternatives(for: breakfast.id, in: draft.plan.id)
        #expect(!offered.isEmpty && offered.count <= 3)
        #expect(!offered.contains { $0.recipeId == oldBreakfast })
        let target = try #require(offered.first).recipeId
        let swapped = try await env.plans.swap(breakfast.id, in: draft.plan.id, to: target)
        #expect(swapped.plan.meal(breakfast.id)?.recipeId == target)

        let events = try await env.repositories.learningEvents.fetchAll().map(\.kind)
        #expect(
            events == [
                .rerolled(recipe: oldDinner, slot: .dinner, reason: .kidsWontEatIt),
                .swapped(from: oldBreakfast, to: target, slot: .breakfast),
            ])
    }

    @Test("a swap to a recipe that is not a safe alternative is refused (AC-8.1)")
    func swapToUnsafeRecipeRefused() async throws {
        let env = ServicesEnv()
        try await env.households.createHousehold(adults: 1, children: 0)
        _ = try await env.safety.confirmSafetyAnswers([RuleRequest(restriction: ServicesFixture.peanut, scope: .household)])
        let draft = try await env.plans.generateWeek()
        let breakfast = try #require(draft.plan.meals.first { $0.slot == .breakfast })

        let error = await serviceError {
            _ = try await env.plans.swap(breakfast.id, in: draft.plan.id, to: ServicesFixture.peanutRecipe)
        }
        #expect(error == .recipeNotOffered(ServicesFixture.peanutRecipe))
        let wrongSlot = await serviceError { _ = try await env.plans.swap(breakfast.id, in: draft.plan.id, to: "d-dal") }
        #expect(wrongSlot == .recipeNotOffered("d-dal"))
        #expect(try await env.storedPlan(draft.plan.id) == draft.plan)
        #expect(try await env.repositories.learningEvents.fetchAll().isEmpty)
    }

    @Test("locked meals are kept by regenerate and cannot be re-rolled (AC-8.3)")
    func lockedMeals() async throws {
        let env = ServicesEnv()
        try await env.onboardWithoutRules()
        let draft = try await env.plans.generateWeek()
        let meal = try #require(draft.plan.meals.first { $0.slot == .dinner })
        let locked = try await env.plans.setLocked(true, meal: meal.id, in: draft.plan.id)
        #expect(locked.plan.meal(meal.id)?.locked == true)

        let reroll = await serviceError { _ = try await env.plans.reroll(meal.id, in: draft.plan.id, reason: nil) }
        #expect(reroll == .mealLocked(meal.id))

        let regenerated = try await env.plans.regenerate(draft.plan.id)
        #expect(regenerated.plan.meal(meal.id) == locked.plan.meal(meal.id))
        #expect(regenerated.report.passedForEveryone)
    }

    @Test("no other safe recipe: re-roll says so and changes nothing")
    func noOtherSafeRecipe() async throws {
        let library = PlanningLibrary(
            recipes: ServicesFixture.recipes.filter { $0.id != "b-poha" && $0.id != "b-upma" },
            ingredients: ServicesFixture.ingredients(), restrictions: ServicesFixture.restrictions,
            contentVersion: "small")
        let env = ServicesEnv(library: library)
        try await env.onboardWithoutRules()
        let draft = try await env.plans.generateWeek()
        let breakfast = try #require(draft.plan.meals.first { $0.slot == .breakfast })

        let error = await serviceError { _ = try await env.plans.reroll(breakfast.id, in: draft.plan.id, reason: nil) }
        #expect(error == .noOtherSafeRecipe(breakfast.id))
        #expect(try await env.plans.alternatives(for: breakfast.id, in: draft.plan.id).isEmpty)
        #expect(try await env.storedPlan(draft.plan.id) == draft.plan)
    }

    @Test("a stale clearance is refused: the household changed after the gate ran (ADR 0007)")
    func staleClearanceRefused() async throws {
        let env = ServicesEnv()
        let household = try await env.onboardWithoutRules()
        let clearance = try SafetyGate.evaluate(household, now: ServicesFixture.now, timeZone: ServicesFixture.utc).get()
        _ = try await env.safety.addRule(RuleRequest(restriction: ServicesFixture.peanut, scope: .household))
        let changed = try await env.household()

        let error = await serviceError {
            _ = try await env.plans.makeWeek(
                household: changed, clearance: clearance, absences: [], now: ServicesFixture.now)
        }
        #expect(error == .clearanceNotValid)
        #expect(try await env.repositories.mealPlans.fetchAll().isEmpty)
    }

    @Test("a clearance that has expired by time is refused, too (G3)")
    func expiredClearanceRefused() async throws {
        let env = ServicesEnv()
        let household = try await env.onboardWithoutRules()
        let clearance = try SafetyGate.evaluate(household, now: ServicesFixture.now, timeZone: ServicesFixture.utc).get()
        let later = ServicesFixture.now.addingTimeInterval(Double(SafetyGate.reconfirmationPeriodDays + 1) * 86_400)

        let error = await serviceError {
            _ = try await env.plans.makeWeek(household: household, clearance: clearance, absences: [], now: later)
        }
        #expect(error == .clearanceNotValid)
    }

    @Test("validator-rejected planner output is emptied, reported, and never stored unsafe (AC-4.2)")
    func sanitizerEmptiesRejectedMeals() async throws {
        let env = ServicesEnv()
        let household = try await env.onboardWithoutRules()
        let engine = PlanningEngine(context: env.context)
        let rule = Rule(
            id: "r", scope: .household, restriction: try #require(ServicesFixture.restrictions.first),
            createdAt: ServicesFixture.now)
        var strict = household
        try strict.addRule(rule, at: ServicesFixture.now)

        // A draft planned without the rule, checked against the household with it (as a planner bug would).
        let draft = try await env.plans.generateWeek()
        let unsafe = draft.plan.meals(using: ServicesFixture.peanutRecipe).map(\.id)
        try #require(!unsafe.isEmpty)
        let checked = try engine.sanitizedDraft(draft.plan, household: strict)
        #expect(checked.report.passedForEveryone)
        for id in unsafe {
            #expect(checked.plan.meal(id)?.recipeId == nil)
            #expect(checked.plan.meal(id)?.emptyReason == .removedByValidator)
        }
        #expect(env.diagnostics.all == [.validatorRejectedPlannerOutput(planId: draft.plan.id, meals: unsafe)])
    }
}
