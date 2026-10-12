import Foundation

/// Proof that the user tapped Approve in the approval sheet (AC-5.2, AC-5.6, ADR 0008).
///
/// Carries no data: its value is that creating one is restricted. Its initialiser may appear
/// only in the approval sheet's button handler (`OMPFeatures/Plan/ApprovalSheet*.swift`) and in
/// tests, which `scripts/lint-safety.sh` enforces (T12). Voice and the share extension can at
/// most open the sheet.
public struct UserConfirmation: Sendable, Hashable {
    public init() {}
}

/// Why a lifecycle transition was refused.
public enum PlanLifecycleError: Error, Sendable, Hashable {
    /// The transition needs a plan in `expected` status but it was `actual`.
    case wrongStatus(expected: PlanStatus, actual: PlanStatus)
    /// The validation report is about another plan.
    case reportForDifferentPlan(reportPlanId: MealPlanID, planId: MealPlanID)
    /// The validation report is for different content than the draft has now.
    case reportForDifferentContent(reportHash: String, planHash: String)
    /// The validator found violations in these meals; approval is not possible (AC-4.2).
    case validationFailed(violatingMeals: [PlannedMealID])
    /// The plan being replaced is not the approved revision the draft was based on.
    case notTheBaseRevision(draftBasedOn: MealPlanID?, previousId: MealPlanID?)
    /// Two plans that must share a series do not.
    case differentSeries
}

/// The result of approving a draft: the approved plan and, for a revision, the previously
/// approved plan now `superseded` (AC-5.7).
public struct PlanApprovalOutcome: Sendable, Hashable {
    public let approved: MealPlan
    public let superseded: MealPlan?

    public init(approved: MealPlan, superseded: MealPlan?) {
        self.approved = approved
        self.superseded = superseded
    }
}

/// The plan state machine (plan section 4.2, ADR 0008). Pure functions over `MealPlan` values;
/// illegal transitions throw `PlanLifecycleError`. Persisting the results is the caller's job.
///
/// ```
/// draft -> approved     approve (UserConfirmation + passing report for the same hash)
/// draft -> discarded    discard
/// approved -> superseded  a newer revision in the series is approved
/// approved -> draft(revision + 1)  any edit (the approved plan stays active, A6)
/// ```
public enum PlanLifecycle {
    /// AC-5.2, AC-5.4, AC-5.7: approve `draft` after the user's tap.
    ///
    /// Requires `draft` to be a draft, `validation` to be a passing report for this plan **and
    /// for its current content hash**, and `previous` to be the approved plan the draft was
    /// based on (`nil` for a first revision). The approval stores approver, time and hash.
    /// Because the passing report covers exactly this content, any `blockedBySafety` flags are
    /// cleared. `previous`, if given, becomes `superseded`.
    public static func approve(
        _ draft: MealPlan,
        replacing previous: MealPlan? = nil,
        confirmation: UserConfirmation,
        validation: ValidationReport,
        now: Date
    ) throws(PlanLifecycleError) -> PlanApprovalOutcome {
        _ = confirmation
        try requireStatus(draft, .draft)
        guard validation.planId == draft.id else {
            throw PlanLifecycleError.reportForDifferentPlan(reportPlanId: validation.planId, planId: draft.id)
        }
        let hash = draft.contentHash
        guard validation.contentHash == hash else {
            throw PlanLifecycleError.reportForDifferentContent(reportHash: validation.contentHash, planHash: hash)
        }
        guard validation.passedForEveryone else {
            throw PlanLifecycleError.validationFailed(violatingMeals: validation.violatingMealIDs)
        }
        guard draft.basedOn == previous?.id else {
            throw PlanLifecycleError.notTheBaseRevision(draftBasedOn: draft.basedOn, previousId: previous?.id)
        }
        var superseded: MealPlan?
        if let previous {
            superseded = try supersede(previous, by: draft)
        }

        var approved = draft
        approved.status = .approved
        approved.approval = PlanApproval(approver: .thisDevice, approvedAt: now, contentHash: hash)
        for index in approved.meals.indices {
            approved.meals[index].blockedBySafety = false
        }
        return PlanApprovalOutcome(approved: approved, superseded: superseded)
    }

    /// AC-5.7: a draft the user discards becomes `discarded`.
    public static func discard(_ draft: MealPlan) throws(PlanLifecycleError) -> MealPlan {
        try requireStatus(draft, .draft)
        var discarded = draft
        discarded.status = .discarded
        return discarded
    }

    /// AC-5.7: the approved plan `approved` becomes `superseded` by `newer`, a later revision of
    /// the same series. Its approval record is kept for history.
    public static func supersede(_ approved: MealPlan, by newer: MealPlan) throws(PlanLifecycleError) -> MealPlan {
        try requireStatus(approved, .approved)
        guard approved.seriesId == newer.seriesId else { throw PlanLifecycleError.differentSeries }
        var superseded = approved
        superseded.status = .superseded
        return superseded
    }

    /// AC-5.4, AC-8.4: the draft revision created when an approved plan is edited:
    /// same series, `revision + 1`, `basedOn` the approved plan, same meals (ids kept so the
    /// diff can pair them), no approval. The approved plan itself is unchanged and stays active
    /// until the revision is approved (A6).
    public static func makeRevision(
        of approved: MealPlan, id: MealPlanID, now: Date
    ) throws(PlanLifecycleError) -> MealPlan {
        try requireStatus(approved, .approved)
        return MealPlan(
            id: id, seriesId: approved.seriesId, revision: approved.revision + 1, basedOn: approved.id,
            weekStart: approved.weekStart, status: .draft, meals: approved.meals, approval: nil,
            contentVersion: approved.contentVersion, createdAt: now)
    }

    /// Applies an edit (swap, re-roll, lock/unlock, regenerate, not eating) to the plan the user
    /// is working on. A draft is edited in place; an approved plan yields a new draft revision
    /// (`makeRevision`) with the edit applied, leaving the approved plan untouched (AC-5.4).
    /// Superseded and discarded plans cannot be edited.
    public static func edit(
        _ plan: MealPlan,
        newRevisionId: MealPlanID,
        now: Date,
        _ change: (inout [PlannedMeal]) -> Void
    ) throws(PlanLifecycleError) -> MealPlan {
        var working: MealPlan
        switch plan.status {
        case .draft:
            working = plan
        case .approved:
            working = try makeRevision(of: plan, id: newRevisionId, now: now)
        case .superseded, .discarded:
            throw PlanLifecycleError.wrongStatus(expected: .draft, actual: plan.status)
        }
        change(&working.meals)
        return working
    }

    /// R1: after a hard-rule change, mark the meals `validation` found unsafe as
    /// `blockedBySafety` and clear the flag on the others. `validation` must be a fresh report
    /// for this plan's current content. The flag is not part of the content hash, so an approved
    /// plan stays approved while its blocked meals are kept off the shopping list and out of
    /// Mark cooked until a fixed revision is approved.
    public static func applySafetyRecheck(
        _ plan: MealPlan, validation: ValidationReport
    ) throws(PlanLifecycleError) -> MealPlan {
        switch plan.status {
        case .draft, .approved:
            break
        case .superseded, .discarded:
            throw PlanLifecycleError.wrongStatus(expected: .approved, actual: plan.status)
        }
        guard validation.planId == plan.id else {
            throw PlanLifecycleError.reportForDifferentPlan(reportPlanId: validation.planId, planId: plan.id)
        }
        let hash = plan.contentHash
        guard validation.contentHash == hash else {
            throw PlanLifecycleError.reportForDifferentContent(reportHash: validation.contentHash, planHash: hash)
        }
        let unsafe = Set(validation.violatingMealIDs)
        var checked = plan
        for index in checked.meals.indices {
            checked.meals[index].blockedBySafety = unsafe.contains(checked.meals[index].id)
        }
        return checked
    }

    /// The plan downstream features read for `series` (plan section 4.2): the highest-revision
    /// plan in `plans` that belongs to the series and is effectively approved, or `nil`.
    public static func activeApprovedPlan(in plans: [MealPlan], series: PlanSeriesID) -> MealPlan? {
        plans
            .filter { $0.seriesId == series && $0.isEffectivelyApproved }
            .max { $0.revision < $1.revision }
    }

    private static func requireStatus(_ plan: MealPlan, _ expected: PlanStatus) throws(PlanLifecycleError) {
        guard plan.status == expected else {
            throw PlanLifecycleError.wrongStatus(expected: expected, actual: plan.status)
        }
    }
}
