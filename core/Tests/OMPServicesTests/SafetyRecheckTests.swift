import Foundation
import OMPDomain
import OMPSafetyCheck
import OMPServices
import Testing

@Suite("R1: hard-rule and content changes re-validate open plans (T18)")
struct SafetyRecheckTests {
    private func validate(_ plan: MealPlan, _ household: Household, uradMayContainPeanut: Bool = false)
        -> ValidationReport
    {
        PlanValidator.validate(
            plan, household: household,
            library: ServicesFixture.safetyLibrary(uradMayContainPeanut: uradMayContainPeanut))
    }

    @Test("adding a peanut rule blocks the approved peanut meals, keeps them off the list, and proposes a fix")
    func ruleAddedAfterApproval() async throws {
        let env = ServicesEnv()
        let approved = try await env.approvedWeek()
        let peanutMeals = Set(approved.meals(using: ServicesFixture.peanutRecipe).map(\.id))
        try #require(!peanutMeals.isEmpty)

        let result = try await env.safety.addRule(
            RuleRequest(restriction: ServicesFixture.peanut, scope: .household))
        #expect(Set(result.recheck.blockedMeals) == peanutMeals)
        #expect(result.recheck.planningRefusal == nil)
        #expect(result.recheck.proposedDrafts.count == 1)

        // The approved plan stays approved and active (the flag is not in the hash) ...
        let stored = try await env.storedPlan(approved.id)
        #expect(stored.status == .approved)
        #expect(stored.isEffectivelyApproved)
        #expect(try await env.plans.activeApprovedPlan(series: approved.seriesId) == stored)
        for meal in stored.meals {
            #expect(meal.blockedBySafety == peanutMeals.contains(meal.id))
        }
        // ... but its peanut meals are no longer on the shopping list or cookable (R1).
        let listed = IngredientRequirements.shoppingMeals(of: stored, today: ServicesFixture.today)
        #expect(!listed.contains { peanutMeals.contains($0.id) })
        #expect(listed.count == stored.meals.count - peanutMeals.count)

        // The proposed fixed draft is a revision with no peanut meal that passes validation.
        let proposedID = try #require(result.recheck.proposedDrafts.first)
        let proposed = try await env.storedPlan(proposedID)
        #expect(proposed.status == .draft)
        #expect(proposed.basedOn == approved.id)
        #expect(proposed.meals(using: ServicesFixture.peanutRecipe).isEmpty)
        #expect(proposed.meals.allSatisfy { !$0.blockedBySafety })
        #expect(validate(proposed, result.household).passedForEveryone)
        #expect(try await env.plans.workingPlan(series: approved.seriesId) == proposed)
        let pending = try await env.plans.pendingDiff(series: approved.seriesId)
        let diff = try #require(pending)
        #expect(Set(diff.listedChanges.compactMap { $0.was?.id }) == peanutMeals)

        // Approving the fix supersedes the old plan; nothing is blocked any more.
        let outcome = try await env.plans.approve(proposedID, confirmation: UserConfirmation())
        #expect(outcome.superseded?.id == approved.id)
        #expect(try await env.storedPlan(approved.id).status == .superseded)
        let activePlan = try await env.plans.activeApprovedPlan(series: approved.seriesId)
        let active = try #require(activePlan)
        #expect(active.id == proposedID)
        #expect(active.meals.allSatisfy { !$0.blockedBySafety })
    }

    @Test("a rule change re-plans the unsafe meals of an open draft (AC-3.5)")
    func ruleAddedToOpenDraft() async throws {
        let env = ServicesEnv()
        try await env.onboardWithoutRules()
        let draft = try await env.plans.generateWeek()
        try #require(!draft.plan.meals(using: ServicesFixture.peanutRecipe).isEmpty)

        let result = try await env.safety.addRule(
            RuleRequest(restriction: ServicesFixture.peanut, scope: .household))
        #expect(result.recheck.fixedDrafts == [draft.plan.id])
        #expect(result.recheck.proposedDrafts.isEmpty)
        let fixed = try await env.storedPlan(draft.plan.id)
        #expect(fixed.meals(using: ServicesFixture.peanutRecipe).isEmpty)
        #expect(fixed.meals.allSatisfy { $0.recipeId != nil })
        #expect(validate(fixed, result.household).passedForEveryone)
        _ = try await env.plans.approve(draft.plan.id, confirmation: UserConfirmation())
    }

    @Test("an existing draft revision is fixed instead of proposing a second one")
    func ruleAddedWithPendingRevision() async throws {
        let env = ServicesEnv()
        let approved = try await env.approvedWeek()
        let nonPeanut = try #require(approved.meals.first { $0.recipeId != ServicesFixture.peanutRecipe })
        let revision = try await env.plans.setLocked(true, meal: nonPeanut.id, in: approved.id)

        let result = try await env.safety.addRule(
            RuleRequest(restriction: ServicesFixture.peanut, scope: .household))
        #expect(result.recheck.proposedDrafts.isEmpty)
        #expect(result.recheck.fixedDrafts == [revision.plan.id])
        #expect(!result.recheck.blockedMeals.isEmpty)
        let fixed = try await env.storedPlan(revision.plan.id)
        #expect(fixed.meals(using: ServicesFixture.peanutRecipe).isEmpty)
        #expect(fixed.meal(nonPeanut.id)?.locked == true)
    }

    @Test("with the gate refused, unsafe meals are only flagged and approval stays impossible")
    func ruleAddedWhileGateRefused() async throws {
        let env = ServicesEnv()
        let approved = try await env.approvedWeek()
        let newcomer = try await env.households.addMember(role: .adult, ageBand: .adult)

        let result = try await env.safety.addRule(
            RuleRequest(restriction: ServicesFixture.peanut, scope: .household))
        #expect(result.recheck.planningRefusal == .safetyUnanswered([newcomer.id]))
        #expect(result.recheck.proposedDrafts.isEmpty)
        #expect(!result.recheck.blockedMeals.isEmpty)
        let stored = try await env.storedPlan(approved.id)
        #expect(stored.meals.filter(\.blockedBySafety).map(\.id) == result.recheck.blockedMeals)
    }

    @Test("a peanut rule for a locked peanut meal: safety beats the lock")
    func lockedUnsafeMealIsReplaced() async throws {
        let env = ServicesEnv()
        try await env.onboardWithoutRules()
        let draft = try await env.plans.generateWeek()
        let peanutMeal = try #require(draft.plan.meals(using: ServicesFixture.peanutRecipe).first)
        _ = try await env.plans.setLocked(true, meal: peanutMeal.id, in: draft.plan.id)

        _ = try await env.safety.addRule(RuleRequest(restriction: ServicesFixture.peanut, scope: .household))
        let fixedPlan = try await env.storedPlan(draft.plan.id)
        let fixed = try #require(fixedPlan.meal(peanutMeal.id))
        #expect(fixed.recipeId != ServicesFixture.peanutRecipe)
        #expect(fixed.locked == false)
        #expect(fixed.reasons.first == .lockedMealNoLongerSafe)
    }

    @Test("removing the rule again clears the blocks on the approved plan")
    func ruleRemovedClearsBlocks() async throws {
        let env = ServicesEnv()
        let approved = try await env.approvedWeek()
        let added = try await env.safety.addRule(RuleRequest(restriction: ServicesFixture.peanut, scope: .household))
        let proposedID = try #require(added.recheck.proposedDrafts.first)
        _ = try await env.plans.discard(proposedID)

        let rule = try #require(added.household.rules.first)
        let removed = try await env.safety.removeRule(rule.id)
        #expect(removed.recheck.isClean)
        #expect(try await env.storedPlan(approved.id).meals.allSatisfy { !$0.blockedBySafety })
    }

    @Test("a rule from outside the catalog is refused; rules always snapshot catalog tags")
    func unknownRestriction() async throws {
        let env = ServicesEnv()
        try await env.households.createHousehold(adults: 1, children: 0)
        let error = await serviceError {
            _ = try await env.safety.confirmSafetyAnswers([RuleRequest(restriction: "made-up", scope: .household)])
        }
        #expect(error == .unknownRestriction("made-up"))
        #expect(try await env.household().rules.isEmpty)
    }

    @Test("a seed contentVersion change triggers the R1 re-check of the approved plan, once")
    func contentVersionChange() async throws {
        let env = ServicesEnv()
        try await env.households.createHousehold(adults: 1, children: 1)
        _ = try await env.safety.confirmSafetyAnswers([
            RuleRequest(restriction: ServicesFixture.peanut, scope: .household)
        ])
        let draft = try await env.plans.generateWeek()
        let approved = try await env.plans.approve(draft.plan.id, confirmation: UserConfirmation()).approved
        let idliMeals = Set(approved.meals(using: "b-idli").map(\.id))
        try #require(!idliMeals.isEmpty)
        #expect(try await env.safety.recheckIfLibraryChanged() == nil)

        // Version 2 of the seed: urad dal may contain peanut.
        let updated = env.withLibrary(ServicesFixture.library(version: "test-2", uradMayContainPeanut: true))
        let recheck = try await updated.safety.recheckIfLibraryChanged()
        let outcome = try #require(recheck)
        #expect(Set(outcome.blockedMeals) == idliMeals)
        #expect(outcome.proposedDrafts.count == 1)
        let stored = try await updated.storedPlan(approved.id)
        #expect(stored.contentVersion == "test-2")
        #expect(stored.isEffectivelyApproved)
        #expect(stored.meals.filter(\.blockedBySafety).count == idliMeals.count)
        let proposed = try await updated.storedPlan(try #require(outcome.proposedDrafts.first))
        #expect(proposed.meals(using: "b-idli").isEmpty)
        let household = try await updated.household()
        #expect(validate(proposed, household, uradMayContainPeanut: true).passedForEveryone)

        // Every open plan is now on version 2: no second re-check.
        #expect(try await updated.safety.recheckIfLibraryChanged() == nil)
    }
}

@Suite("Approval always re-validates at call time (T13 review-1, T18)")
struct ApprovalRevalidationTests {
    @Test("a rule added behind the services' back after validation makes approval fail")
    func ruleChangedBetweenValidationAndApprove() async throws {
        let env = ServicesEnv()
        try await env.onboardWithoutRules()
        let draft = try await env.plans.generateWeek()
        #expect(draft.report.passedForEveryone)
        let peanutMeals = draft.plan.meals(using: ServicesFixture.peanutRecipe).map(\.id)
        try #require(!peanutMeals.isEmpty)

        // The stored rules change without the R1 re-check (for example a sync or a crash).
        var household = try await env.household()
        let peanut = try #require(ServicesFixture.restrictions.first)
        try household.addRule(
            Rule(id: "rule-x", scope: .household, restriction: peanut, createdAt: ServicesFixture.now),
            at: ServicesFixture.now)
        try await env.repositories.household.replace(with: household)

        let error = await serviceError {
            _ = try await env.plans.approve(draft.plan.id, confirmation: UserConfirmation())
        }
        #expect(error == .validationFailed(violatingMeals: peanutMeals))
        #expect(try await env.storedPlan(draft.plan.id).status == .draft)

        // The launch re-check repairs it, after which approval succeeds.
        let outcome = try await env.safety.recheckOpenPlans()
        #expect(outcome.fixedDrafts == [draft.plan.id])
        let approved = try await env.plans.approve(draft.plan.id, confirmation: UserConfirmation()).approved
        #expect(approved.meals(using: ServicesFixture.peanutRecipe).isEmpty)
    }

    @Test("approve racing a rule change never leaves an unsafe, unblocked approved meal")
    func approveRacesRuleChange() async throws {
        let env = ServicesEnv()
        try await env.onboardWithoutRules()
        let draft = try await env.plans.generateWeek()

        let approval = Task { try await env.plans.approve(draft.plan.id, confirmation: UserConfirmation()) }
        let change = Task {
            try await env.safety.addRule(RuleRequest(restriction: ServicesFixture.peanut, scope: .household))
        }
        _ = await approval.result
        let changed = try await change.value

        let plans = try await env.repositories.mealPlans.fetchAll()
        let household = changed.household
        for plan in plans where plan.isEffectivelyApproved {
            let report = PlanValidator.validate(plan, household: household, library: ServicesFixture.safetyLibrary())
            let unsafe = Set(report.violatingMealIDs)
            for meal in plan.meals where unsafe.contains(meal.id) {
                #expect(meal.blockedBySafety, "approved meal \(meal.id) is unsafe but not blocked")
            }
        }
        for plan in plans where plan.status == .draft {
            let report = PlanValidator.validate(plan, household: household, library: ServicesFixture.safetyLibrary())
            #expect(report.passedForEveryone)
        }
    }
}
