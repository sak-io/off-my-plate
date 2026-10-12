import Foundation
import OMPDomain
import Testing

@Suite("Plan lifecycle (ADR 0008, AC-5.1, AC-5.2, AC-5.4, AC-5.7, AC-8.4, R1)")
struct PlanLifecycleTests {
    typealias Fixture = PlanFixture

    // MARK: approve

    @Test("AC-5.1: a new plan is a draft with no approval")
    func newPlanIsDraft() {
        let plan = Fixture.draft()
        #expect(plan.status == .draft)
        #expect(plan.approval == nil)
        #expect(!plan.isEffectivelyApproved)
    }

    @Test("AC-5.2: approve stores approver, time and the content hash; the plan is effectively approved")
    func approveDraft() throws {
        let draft = Fixture.draft()
        let outcome = try PlanLifecycle.approve(
            draft, confirmation: UserConfirmation(), validation: Fixture.report(for: draft), now: Sample.later)
        #expect(outcome.superseded == nil)
        let approved = outcome.approved
        #expect(approved.status == .approved)
        #expect(approved.approval == PlanApproval(approver: .thisDevice, approvedAt: Sample.later, contentHash: draft.contentHash))
        #expect(approved.isEffectivelyApproved)
        #expect(approved.meals == draft.meals)
        #expect(approved.id == draft.id && approved.revision == draft.revision)
    }

    @Test("approve refuses a plan that is not a draft", arguments: [PlanStatus.approved, .superseded, .discarded])
    func approveRequiresDraft(status: PlanStatus) {
        var plan = Fixture.draft()
        plan.status = status
        let error = Fixture.error {
            try PlanLifecycle.approve(
                plan, confirmation: UserConfirmation(), validation: Fixture.report(for: plan), now: Sample.later)
        }
        #expect(error == PlanLifecycleError.wrongStatus(expected: .draft, actual: status))
    }

    @Test("approve refuses a report for another plan")
    func approveRejectsOtherPlanReport() {
        let draft = Fixture.draft()
        let other = Fixture.draft(id: "plan-other")
        let error = Fixture.error {
            try PlanLifecycle.approve(
                draft, confirmation: UserConfirmation(), validation: Fixture.report(for: other), now: Sample.later)
        }
        #expect(error == PlanLifecycleError.reportForDifferentPlan(reportPlanId: "plan-other", planId: "plan-1"))
    }

    @Test("approve refuses a passing report for different content (validated, then edited)")
    func approveRejectsStaleReport() {
        let validated = Fixture.draft()
        let report = Fixture.report(for: validated)
        var edited = validated
        edited.meals[0].recipeId = "poha"
        let error = Fixture.error {
            try PlanLifecycle.approve(edited, confirmation: UserConfirmation(), validation: report, now: Sample.later)
        }
        #expect(error == PlanLifecycleError.reportForDifferentContent(reportHash: validated.contentHash, planHash: edited.contentHash))
    }

    @Test("approve refuses a failing report and names the failing meals")
    func approveRejectsFailingReport() {
        let draft = Fixture.draft()
        let report = Fixture.report(
            for: draft,
            violations: [
                Violation(mealId: "meal-2", memberId: Fixture.child, kind: .excludedTag(.peanut, ingredient: "peanut")),
                Violation(mealId: "meal-2", memberId: Fixture.adult, kind: .unknownRecipe("rajma-chawal")),
                Violation(mealId: "meal-1", memberId: Fixture.child, kind: .unverifiedIngredient("hing")),
            ])
        let error = Fixture.error {
            try PlanLifecycle.approve(draft, confirmation: UserConfirmation(), validation: report, now: Sample.later)
        }
        #expect(error == PlanLifecycleError.validationFailed(violatingMeals: ["meal-2", "meal-1"]))
    }

    @Test("approve clears stale blockedBySafety flags, because the passing report covers this exact content")
    func approveClearsBlockedFlags() throws {
        var draft = Fixture.draft()
        draft.meals[1].blockedBySafety = true
        let approved = try Fixture.approved(draft)
        #expect(approved.meals.allSatisfy { !$0.blockedBySafety })
        #expect(approved.isEffectivelyApproved)
    }

    // MARK: revisions and supersede

    @Test("AC-5.4: editing an approved plan creates a draft revision and leaves the approved plan active")
    func editApprovedCreatesRevision() throws {
        let approved = try Fixture.approved()
        let revision = try PlanLifecycle.edit(approved, newRevisionId: "plan-2", now: Sample.later) { meals in
            meals[1].recipeId = "chole-chawal"
        }
        #expect(revision.id == "plan-2")
        #expect(revision.status == .draft)
        #expect(revision.seriesId == approved.seriesId)
        #expect(revision.revision == approved.revision + 1)
        #expect(revision.basedOn == approved.id)
        #expect(revision.approval == nil)
        #expect(revision.createdAt == Sample.later)
        #expect(revision.meals.map(\.id) == approved.meals.map(\.id))
        #expect(revision.meals[1].recipeId == "chole-chawal")
        // The approved plan is a value: untouched, still effectively approved (A6).
        #expect(approved.isEffectivelyApproved)
        #expect(approved.meals[1].recipeId == "rajma-chawal")
        #expect(PlanLifecycle.activeApprovedPlan(in: [approved, revision], series: "series-1") == approved)
    }

    @Test("AC-8.4: a lock change on an approved plan also creates a revision")
    func lockOnApprovedCreatesRevision() throws {
        let approved = try Fixture.approved()
        let revision = try PlanLifecycle.edit(approved, newRevisionId: "plan-2", now: Sample.later) { meals in
            meals[0].locked = true
        }
        #expect(revision.status == .draft && revision.basedOn == approved.id)
        #expect(revision.contentHash != approved.contentHash)
    }

    @Test("editing a draft changes it in place without a new revision")
    func editDraftInPlace() throws {
        let draft = Fixture.draft()
        let edited = try PlanLifecycle.edit(draft, newRevisionId: "unused", now: Sample.later) { meals in
            meals[0].recipeId = "poha"
        }
        #expect(edited.id == draft.id && edited.revision == draft.revision && edited.status == .draft)
        #expect(edited.meals[0].recipeId == "poha")
    }

    @Test("superseded and discarded plans cannot be edited", arguments: [PlanStatus.superseded, .discarded])
    func editRefusesClosedPlans(status: PlanStatus) {
        var plan = Fixture.draft()
        plan.status = status
        let error = Fixture.error {
            try PlanLifecycle.edit(plan, newRevisionId: "plan-2", now: Sample.later) { _ in }
        }
        #expect(error == PlanLifecycleError.wrongStatus(expected: .draft, actual: status))
    }

    @Test("makeRevision needs an approved plan")
    func makeRevisionRequiresApproved() {
        let error = Fixture.error {
            try PlanLifecycle.makeRevision(of: Fixture.draft(), id: "plan-2", now: Sample.later)
        }
        #expect(error == PlanLifecycleError.wrongStatus(expected: .approved, actual: .draft))
    }

    @Test("AC-5.7: approving a revision supersedes the approved plan it was based on")
    func approveRevisionSupersedes() throws {
        let approved = try Fixture.approved()
        let revision = try PlanLifecycle.edit(approved, newRevisionId: "plan-2", now: Sample.later) { meals in
            meals[1].recipeId = "chole-chawal"
        }
        let outcome = try PlanLifecycle.approve(
            revision, replacing: approved, confirmation: UserConfirmation(),
            validation: Fixture.report(for: revision), now: Sample.later)
        #expect(outcome.approved.status == .approved && outcome.approved.isEffectivelyApproved)
        let superseded = try #require(outcome.superseded)
        #expect(superseded.id == approved.id)
        #expect(superseded.status == .superseded)
        #expect(superseded.approval == approved.approval)
        #expect(!superseded.isEffectivelyApproved)
        #expect(
            PlanLifecycle.activeApprovedPlan(in: [superseded, outcome.approved], series: "series-1")
                == outcome.approved)
    }

    @Test("approving a revision needs the approved plan it was based on")
    func approveRevisionNeedsItsBase() throws {
        let approved = try Fixture.approved()
        let revision = try PlanLifecycle.makeRevision(of: approved, id: "plan-2", now: Sample.later)
        let report = Fixture.report(for: revision)

        let missing = Fixture.error {
            try PlanLifecycle.approve(revision, confirmation: UserConfirmation(), validation: report, now: Sample.later)
        }
        #expect(missing == PlanLifecycleError.notTheBaseRevision(draftBasedOn: "plan-1", previousId: nil))

        let stranger = try Fixture.approved(Fixture.draft(id: "plan-x"))
        let wrong = Fixture.error {
            try PlanLifecycle.approve(
                revision, replacing: stranger, confirmation: UserConfirmation(), validation: report, now: Sample.later)
        }
        #expect(wrong == PlanLifecycleError.notTheBaseRevision(draftBasedOn: "plan-1", previousId: "plan-x"))

        var alreadySuperseded = approved
        alreadySuperseded.status = .superseded
        let stale = Fixture.error {
            try PlanLifecycle.approve(
                revision, replacing: alreadySuperseded, confirmation: UserConfirmation(), validation: report,
                now: Sample.later)
        }
        #expect(stale == PlanLifecycleError.wrongStatus(expected: .approved, actual: .superseded))
    }

    @Test("a first draft cannot replace an approved plan")
    func firstDraftCannotReplace() throws {
        let approved = try Fixture.approved()
        let draft = Fixture.draft(id: "plan-2")
        let error = Fixture.error {
            try PlanLifecycle.approve(
                draft, replacing: approved, confirmation: UserConfirmation(), validation: Fixture.report(for: draft),
                now: Sample.later)
        }
        #expect(error == PlanLifecycleError.notTheBaseRevision(draftBasedOn: nil, previousId: "plan-1"))
    }

    @Test("supersede needs an approved plan of the same series")
    func supersedeRules() throws {
        let approved = try Fixture.approved()
        #expect(
            Fixture.error { try PlanLifecycle.supersede(approved, by: Fixture.draft(id: "p", series: "series-2")) }
                == PlanLifecycleError.differentSeries)
        #expect(
            Fixture.error { try PlanLifecycle.supersede(Fixture.draft(), by: Fixture.draft(id: "p")) }
                == PlanLifecycleError.wrongStatus(expected: .approved, actual: .draft))
        let superseded = try PlanLifecycle.supersede(approved, by: Fixture.draft(id: "p"))
        #expect(superseded.status == .superseded)
    }

    // MARK: discard

    @Test("AC-5.7: a discarded draft becomes discarded")
    func discardDraft() throws {
        let discarded = try PlanLifecycle.discard(Fixture.draft())
        #expect(discarded.status == .discarded)
    }

    @Test("only a draft can be discarded", arguments: [PlanStatus.approved, .superseded, .discarded])
    func discardRequiresDraft(status: PlanStatus) {
        var plan = Fixture.draft()
        plan.status = status
        #expect(Fixture.error { try PlanLifecycle.discard(plan) } == PlanLifecycleError.wrongStatus(expected: .draft, actual: status))
    }

    // MARK: R1 safety re-check

    @Test("R1: a re-check marks unsafe meals blocked, keeps the approval and excludes them downstream")
    func safetyRecheckBlocksMeals() throws {
        let approved = try Fixture.approved()
        let report = Fixture.report(
            for: approved,
            violations: [
                Violation(mealId: "meal-2", memberId: Fixture.child, kind: .excludedTag(.peanut, ingredient: "peanut"))
            ])
        let checked = try PlanLifecycle.applySafetyRecheck(approved, validation: report)
        #expect(checked.meals.map(\.blockedBySafety) == [false, true, false])
        #expect(checked.status == .approved)
        #expect(checked.isEffectivelyApproved)
        #expect(checked.usableApprovedMeals.map(\.id) == ["meal-1", "meal-3"])
    }

    @Test("R1: a passing re-check clears earlier blocks")
    func passingRecheckClears() throws {
        var approved = try Fixture.approved()
        approved.meals[1].blockedBySafety = true
        let checked = try PlanLifecycle.applySafetyRecheck(approved, validation: Fixture.report(for: approved))
        #expect(checked.meals.allSatisfy { !$0.blockedBySafety })
    }

    @Test("R1: a re-check needs a report for this plan's current content and an open plan")
    func recheckPreconditions() throws {
        let approved = try Fixture.approved()
        var edited = approved
        edited.meals[0].recipeId = "poha"
        #expect(
            Fixture.error { try PlanLifecycle.applySafetyRecheck(edited, validation: Fixture.report(for: approved)) }
                == PlanLifecycleError.reportForDifferentContent(reportHash: approved.contentHash, planHash: edited.contentHash))
        let other = Fixture.draft(id: "plan-other")
        #expect(
            Fixture.error { try PlanLifecycle.applySafetyRecheck(approved, validation: Fixture.report(for: other)) }
                == PlanLifecycleError.reportForDifferentPlan(reportPlanId: "plan-other", planId: "plan-1"))
        var discarded = Fixture.draft()
        discarded.status = .discarded
        #expect(
            Fixture.error { try PlanLifecycle.applySafetyRecheck(discarded, validation: Fixture.report(for: discarded)) }
                == PlanLifecycleError.wrongStatus(expected: .approved, actual: .discarded))
        // A draft can be re-checked too.
        let draft = Fixture.draft()
        #expect(Fixture.error { try PlanLifecycle.applySafetyRecheck(draft, validation: Fixture.report(for: draft)) } == nil)
    }

    // MARK: active plan

    @Test("the active plan is the highest effectively approved revision of the series")
    func activeApprovedPlanSelection() throws {
        let first = try Fixture.approved()
        var tampered = try Fixture.approved(Fixture.draft(id: "plan-3"))
        tampered.revision = 3
        tampered.meals[0].recipeId = "poha"
        let otherSeries = try Fixture.approved(Fixture.draft(id: "plan-9", series: "series-2"))
        let draft = Fixture.draft(id: "plan-4")
        let plans = [first, tampered, otherSeries, draft]
        #expect(PlanLifecycle.activeApprovedPlan(in: plans, series: "series-1") == first)
        #expect(PlanLifecycle.activeApprovedPlan(in: plans, series: "series-2") == otherSeries)
        #expect(PlanLifecycle.activeApprovedPlan(in: [draft], series: "series-1") == nil)
    }
}
