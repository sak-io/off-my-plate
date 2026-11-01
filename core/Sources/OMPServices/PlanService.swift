import Foundation
import OMPDomain

/// Planning and approval (AC-3.1, AC-4.2, AC-5.x, AC-8.x, A6; plan sections 4.2 and 5; task T18).
///
/// - Every planning entry point evaluates the safety gate itself and plans with that fresh
///   clearance (AC-3.1); a refusal surfaces as `.gateRefused(reason)`.
/// - Every draft is validated with `PlanValidator` before it is returned or stored (AC-4.2).
/// - `approve` re-validates at call time against the current rules and library, never trusting
///   a report from the caller, and saves the approved plan and the superseded one atomically.
/// - Editing an approved plan creates a draft revision; the approved plan stays active until the
///   revision is approved (AC-5.4, A6).
/// - Swaps and re-rolls are logged as learning events (AC-8.2, AC-12.1).
public final class PlanService: Sendable {
    let engine: PlanningEngine

    public init(context: ServiceContext) {
        self.engine = PlanningEngine(context: context)
    }

    var context: ServiceContext { engine.context }

    // MARK: Queries (plan section 12a #3)

    /// The series the Plan tab opens on: that of the most recently created draft or approved plan.
    public func currentSeriesID() async throws -> PlanSeriesID? {
        let plans = try await context.repositories.mealPlans.fetchAll()
        return plans.filter { $0.status == .draft || $0.status == .approved }
            .max { $0.createdAt < $1.createdAt }?.seriesId
    }

    /// What the Plan tab shows: the open draft of `series`, else its active approved plan.
    public func workingPlan(series: PlanSeriesID) async throws -> MealPlan? {
        let plans = try await context.repositories.mealPlans.fetchSeries(series)
        return PlanningEngine.workingPlan(in: plans, series: series)
    }

    /// What the shopping list and Mark cooked read (plan section 4.2): the effectively approved
    /// plan of `series`, even while a draft revision is pending (A6).
    public func activeApprovedPlan(series: PlanSeriesID) async throws -> MealPlan? {
        let plans = try await context.repositories.mealPlans.fetchSeries(series)
        return PlanLifecycle.activeApprovedPlan(in: plans, series: series)
    }

    /// Whether `series` has an approved plan and a draft revision of it waiting for approval.
    public func hasPendingChanges(series: PlanSeriesID) async throws -> Bool {
        try await pendingDiff(series: series) != nil
    }

    /// The approval sheet's diff (AC-5.4): the active approved plan against the open draft
    /// revision, or `nil` when there is no pending revision.
    public func pendingDiff(series: PlanSeriesID) async throws -> PlanDiff? {
        let plans = try await context.repositories.mealPlans.fetchSeries(series)
        guard let approved = PlanLifecycle.activeApprovedPlan(in: plans, series: series),
            let draft = PlanningEngine.openDraft(in: plans), draft.basedOn == approved.id
        else { return nil }
        return PlanDiff(from: approved, to: draft)
    }

    // MARK: Planning

    /// Generates the next week's draft (AC-1.5, AC-5.1; R8): it starts today for the first
    /// plan, otherwise the day after the last approved plan ends, never before today
    /// (`PlanDateRange.startDate`).
    ///
    /// - Throws: `.gateRefused` (AC-3.1), `.openDraftExists` when a first draft is still open.
    public func generateWeek(absences: Set<MealAbsence> = []) async throws -> ValidatedPlan {
        try await context.serialized {
            let household = try await engine.requireHousehold()
            let now = context.clock.now
            let clearance = try engine.clearance(for: household, now: now)
            return try await makeWeek(household: household, clearance: clearance, absences: absences, now: now)
        }
    }

    /// The planning core of `generateWeek`, separate so tests can hand it a stale clearance.
    func makeWeek(
        household: Household, clearance: SafetyClearance, absences: Set<MealAbsence>, now: Date
    ) async throws -> ValidatedPlan {
        let plans = try await context.repositories.mealPlans.fetchAll()
        if let open = plans.first(where: { $0.status == .draft && $0.basedOn == nil }) {
            throw ServiceError.openDraftExists(open.id)
        }
        let previousEnd = plans.filter(\.isEffectivelyApproved).map(\.endDate).max()
        let today = LocalDate(now, in: engine.timeZone)
        let request = WeekPlanRequest(
            planId: engine.newPlanID(), seriesId: PlanSeriesID(context.makeID()),
            weekStart: PlanDateRange.startDate(previousEnd: previousEnd, today: today), absences: absences)
        let signals = try await engine.signals(now: now)
        let library = engine.library.planner
        let timeZone = engine.timeZone
        let plan = try mappingDomainErrors {
            try WeekPlanner.generateWeek(
                clearance: clearance, household: household, library: library, request: request, signals: signals,
                now: now, timeZone: timeZone)
        }
        let validated = try engine.sanitizedDraft(plan, household: household)
        try await context.repositories.mealPlans.save(validated.plan)
        return validated
    }

    /// Regenerates the working plan (AC-8.3): locked meals that are still safe are kept.
    public func regenerate(_ planID: MealPlanID, keepingLocked: Bool = true) async throws -> ValidatedPlan {
        try await edit(planID, requiresClearance: true) { plan, household, clearance, signals, now in
            guard let clearance else { throw ServiceError.clearanceNotValid }
            return try WeekPlanner.regenerate(
                plan, keepingLocked: keepingLocked, clearance: clearance, household: household,
                library: engine.library.planner, signals: signals, now: now, timeZone: engine.timeZone)
        }.validated
    }

    /// Up to `limit` safe alternatives for a meal (AC-8.1). Each one is also checked by the
    /// independent validator before it is offered.
    public func alternatives(
        for mealID: PlannedMealID, in planID: MealPlanID, reason: RerollReason? = nil, limit: Int = 3
    ) async throws -> [MealAlternative] {
        try await context.serialized {
            let plan = try await engine.requireWorkingPlan(planID)
            let household = try await engine.requireHousehold()
            let now = context.clock.now
            let clearance = try engine.clearance(for: household, now: now)
            let signals = try await engine.signals(now: now)
            return try validatedAlternatives(
                for: mealID, in: plan, reason: reason, limit: limit, household: household, clearance: clearance,
                signals: signals, now: now)
        }
    }

    /// Swaps a meal to one of its offered alternatives (AC-8.1) and logs a `.swapped` event.
    ///
    /// - Throws: `.recipeNotOffered` when `recipeID` is not a currently valid alternative.
    public func swap(_ mealID: PlannedMealID, in planID: MealPlanID, to recipeID: RecipeID) async throws -> ValidatedPlan {
        let result = try await edit(planID, requiresClearance: true, mealID: mealID) {
            plan, household, clearance, signals, now in
            guard let clearance else { throw ServiceError.clearanceNotValid }
            let offered = try validatedAlternatives(
                for: mealID, in: plan, reason: nil, limit: Int.max, household: household, clearance: clearance,
                signals: signals, now: now)
            guard let choice = offered.first(where: { $0.recipeId == recipeID }) else {
                throw ServiceError.recipeNotOffered(recipeID)
            }
            return plan.meals.map { $0.id == mealID ? $0.replacingRecipe(with: choice) : $0 }
        }
        if let from = result.before?.recipeId, let meal = result.before {
            try await logEvent(.swapped(from: from, to: recipeID, slot: meal.slot), now: result.now)
        }
        return result.validated
    }

    /// "Pick for me" (AC-8.2): replaces a meal with a different safe recipe and logs a
    /// `.rerolled` event with the reason.
    ///
    /// - Throws: `.noOtherSafeRecipe` when nothing else is safe for that meal.
    public func reroll(_ mealID: PlannedMealID, in planID: MealPlanID, reason: RerollReason?) async throws
        -> ValidatedPlan
    {
        let result = try await edit(planID, requiresClearance: true, mealID: mealID) {
            plan, household, clearance, signals, now in
            guard let clearance else { throw ServiceError.clearanceNotValid }
            let replacement = try WeekPlanner.reroll(
                mealID, in: plan, reason: reason, clearance: clearance, household: household,
                library: engine.library.planner, signals: signals, now: now, timeZone: engine.timeZone)
            guard let replacement else { throw ServiceError.noOtherSafeRecipe(mealID) }
            return plan.meals.map { $0.id == mealID ? replacement : $0 }
        }
        if let recipe = result.before?.recipeId, let meal = result.before {
            try await logEvent(.rerolled(recipe: recipe, slot: meal.slot, reason: reason), now: result.now)
        }
        return result.validated
    }

    /// Locks or unlocks a meal (AC-8.3). On an approved plan this creates a draft revision,
    /// which needs the gate to pass (AC-3.3: no new draft while someone is unasked).
    public func setLocked(_ locked: Bool, meal mealID: PlannedMealID, in planID: MealPlanID) async throws
        -> ValidatedPlan
    {
        try await edit(planID, requiresClearance: nil) { plan, _, _, _, _ in
            guard plan.meal(mealID) != nil else { throw ServiceError.mealNotFound(mealID) }
            return plan.meals.map { meal in
                guard meal.id == mealID else { return meal }
                var copy = meal
                copy.locked = locked
                return copy
            }
        }.validated
    }

    /// Discards a draft (AC-5.7). An approved plan cannot be discarded.
    @discardableResult
    public func discard(_ planID: MealPlanID) async throws -> MealPlan {
        try await context.serialized {
            guard let plan = try await context.repositories.mealPlans.fetch(id: planID) else {
                throw ServiceError.planNotFound(planID)
            }
            let discarded = try mappingDomainErrors { try PlanLifecycle.discard(plan) }
            try await context.repositories.mealPlans.save(discarded)
            return discarded
        }
    }

    // MARK: Approval

    /// Approves a draft after the user's tap in the approval sheet (AC-5.2, AC-5.4, AC-5.6,
    /// AC-5.7). Under the service lock it re-reads the household, refuses while anyone is
    /// unasked (U4), runs `PlanValidator` against the **current** rules and library (never a
    /// report from the caller), approves through `PlanLifecycle`, and saves the approved plan
    /// and the superseded previous revision in one atomic save (TR-2).
    ///
    /// - Throws: `.gateRefused`, `.validationFailed`, `.lifecycle(...)`, `.planNotFound`.
    @discardableResult
    public func approve(_ planID: MealPlanID, confirmation: UserConfirmation) async throws -> PlanApprovalOutcome {
        try await context.serialized {
            guard var draft = try await context.repositories.mealPlans.fetch(id: planID) else {
                throw ServiceError.planNotFound(planID)
            }
            let household = try await engine.requireHousehold()
            if let refusal = SafetyGate.approvalRefusal(for: household) {
                throw ServiceError.gateRefused(refusal)
            }
            var previous: MealPlan?
            if let baseID = draft.basedOn {
                guard let base = try await context.repositories.mealPlans.fetch(id: baseID) else {
                    throw ServiceError.planNotFound(baseID)
                }
                previous = base
            }
            draft.contentVersion = engine.library.contentVersion
            let report = engine.validate(draft, household: household)
            guard report.passedForEveryone else {
                throw ServiceError.validationFailed(violatingMeals: report.violatingMealIDs)
            }
            let now = context.clock.now
            let candidate = draft
            let replaced = previous
            let outcome = try mappingDomainErrors {
                try PlanLifecycle.approve(
                    candidate, replacing: replaced, confirmation: confirmation, validation: report, now: now)
            }
            var batch = [outcome.approved]
            if let superseded = outcome.superseded {
                batch.append(superseded)
            }
            try await context.repositories.mealPlans.save(batch)
            return outcome
        }
    }

    // MARK: Private

    /// The result of `edit`: the validated working plan and the edited meal before the change.
    struct EditResult {
        var validated: ValidatedPlan
        var before: PlannedMeal?
        var now: Date
    }

    /// Applies a change to the working plan `planID` (a draft in place; an approved plan as a
    /// new draft revision, AC-5.4), then validates and saves it.
    ///
    /// - Parameters:
    ///   - requiresClearance: `true` evaluates the gate and passes the clearance; `nil` does so
    ///     only when the edit creates a revision of an approved plan (AC-3.3).
    ///   - change: returns the new meals.
    private func edit(
        _ planID: MealPlanID,
        requiresClearance: Bool?,
        mealID: PlannedMealID? = nil,
        _ change: (MealPlan, Household, SafetyClearance?, PlannerSignals, Date) throws -> [PlannedMeal]
    ) async throws -> EditResult {
        try await context.serialized {
            let working = try await engine.requireWorkingPlan(planID)
            let household = try await engine.requireHousehold()
            let now = context.clock.now
            let needsClearance = requiresClearance ?? (working.status == .approved)
            var clearance: SafetyClearance?
            var signals = PlannerSignals()
            if needsClearance {
                clearance = try engine.clearance(for: household, now: now)
                signals = try await engine.signals(now: now)
            }
            let meals = try mappingDomainErrors { try change(working, household, clearance, signals, now) }
            let revisionID = engine.newPlanID()
            let edited = try mappingDomainErrors {
                try PlanLifecycle.edit(working, newRevisionId: revisionID, now: now) { $0 = meals }
            }
            let validated = try engine.sanitizedDraft(edited, household: household)
            try await context.repositories.mealPlans.save(validated.plan)
            let before = mealID.flatMap { working.meal($0) }
            return EditResult(validated: validated, before: before, now: now)
        }
    }

    private func validatedAlternatives(
        for mealID: PlannedMealID, in plan: MealPlan, reason: RerollReason?, limit: Int, household: Household,
        clearance: SafetyClearance, signals: PlannerSignals, now: Date
    ) throws -> [MealAlternative] {
        let library = engine.library.planner
        let timeZone = engine.timeZone
        let candidates = try mappingDomainErrors {
            try WeekPlanner.alternatives(
                for: mealID, in: plan, reason: reason, limit: Int.max, clearance: clearance, household: household,
                library: library, signals: signals, now: now, timeZone: timeZone)
        }
        var accepted: [MealAlternative] = []
        var anyRejected = false
        for alternative in candidates {
            guard accepted.count < limit else { break }
            var trial = plan
            trial.meals = plan.meals.map { $0.id == mealID ? $0.replacingRecipe(with: alternative) : $0 }
            let report = engine.validate(trial, household: household)
            if report.violations.contains(where: { $0.mealId == mealID }) {
                anyRejected = true
            } else {
                accepted.append(alternative)
            }
        }
        if anyRejected {
            // The planner offered a recipe the validator rejects: a planner bug (plan section 5).
            context.diagnostics(.validatorRejectedPlannerOutput(planId: plan.id, meals: [mealID]))
        }
        return accepted
    }

    private func logEvent(_ kind: LearningEventKind, now: Date) async throws {
        let event = LearningEvent(id: LearningEventID(context.makeID()), kind: kind, at: now)
        try await context.repositories.learningEvents.save(event)
    }
}
