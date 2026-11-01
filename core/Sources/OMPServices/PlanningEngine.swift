import Foundation
import OMPDomain
import OMPSafetyCheck

/// A draft (or plan) together with the validator report produced for exactly its content, at
/// call time, against the household's current hard rules (AC-4.2).
public struct ValidatedPlan: Sendable, Hashable {
    public let plan: MealPlan
    public let report: ValidationReport

    public init(plan: MealPlan, report: ValidationReport) {
        self.plan = plan
        self.report = report
    }
}

/// What an R1 safety re-check did (plan R1, V1; AC-3.5).
public struct SafetyRecheckOutcome: Sendable, Hashable {
    /// Meals of active approved plans now flagged `blockedBySafety`: kept off the shopping list
    /// and out of Mark cooked until a fixed revision is approved.
    public internal(set) var blockedMeals: [PlannedMealID] = []
    /// Open drafts whose unsafe meals were replaced (or emptied when nothing safe remains).
    public internal(set) var fixedDrafts: [MealPlanID] = []
    /// New draft revisions proposed to replace blocked approved meals (the approved plan
    /// stays active until one is approved, A6).
    public internal(set) var proposedDrafts: [MealPlanID] = []
    /// Set when unsafe meals were found but no fix could be planned because the safety gate
    /// refuses (for example a member is unasked). The unsafe meals are flagged, and approval
    /// stays impossible until they are fixed.
    public internal(set) var planningRefusal: GateRefusal?

    public init() {}

    /// Whether nothing unsafe was found.
    public var isClean: Bool {
        blockedMeals.isEmpty && fixedDrafts.isEmpty && proposedDrafts.isEmpty && planningRefusal == nil
    }
}

/// The shared, non-locking core of the services. Callers hold the service lock
/// (`ServiceContext.serialized`) around every sequence that writes.
///
/// Invariants it maintains:
/// - Every draft it returns or stores was validated at call time with `PlanValidator` against
///   the current household and library, and passes (AC-4.2). Meals the validator rejects
///   after planning are emptied (`.removedByValidator`) and reported as a programmer error.
/// - It never accepts a `ValidationReport` or a `SafetyClearance` from outside: both are
///   produced here, immediately before use.
struct PlanningEngine: Sendable {
    let context: ServiceContext

    var repositories: Repositories { context.repositories }
    var library: PlanningLibrary { context.library }
    var timeZone: TimeZone { context.clock.timeZone }

    /// Cook-log entries older than this are not passed to the planner (plan section 5 step 1).
    static let cookLogWindowDays = 14

    // MARK: Loading

    func requireHousehold() async throws -> Household {
        guard let household = try await repositories.household.fetch() else { throw ServiceError.noHousehold }
        return household
    }

    /// A fresh clearance for `household` at `now`, or `.gateRefused`.
    func clearance(for household: Household, now: Date) throws -> SafetyClearance {
        switch SafetyGate.evaluate(household, now: now, timeZone: timeZone) {
        case .success(let clearance): return clearance
        case .failure(let refusal): throw ServiceError.gateRefused(refusal)
        }
    }

    /// Pantry, Facts and the recent cook log for scoring (they never affect safety, AC-12.6).
    func signals(now: Date) async throws -> PlannerSignals {
        let pantry = try await repositories.pantry.fetchAll()
        let facts = try await repositories.facts.fetchAll()
        let cutoff = now.addingTimeInterval(-Double(PlanningEngine.cookLogWindowDays) * 86_400)
        let cookLog = try await repositories.cookLogs.fetchAll().filter { $0.cookedAt >= cutoff }
        return PlannerSignals(pantry: pantry, facts: facts, cookLog: cookLog)
    }

    func newPlanID() -> MealPlanID {
        MealPlanID(context.makeID())
    }

    // MARK: Working plan

    /// The highest-revision draft of `plans` (one series).
    static func openDraft(in plans: [MealPlan]) -> MealPlan? {
        plans.filter { $0.status == .draft }.max { $0.revision < $1.revision }
    }

    /// What the Plan tab shows for a series: its open draft, else its active approved plan.
    static func workingPlan(in plans: [MealPlan], series: PlanSeriesID) -> MealPlan? {
        let inSeries = plans.filter { $0.seriesId == series }
        return openDraft(in: inSeries) ?? PlanLifecycle.activeApprovedPlan(in: inSeries, series: series)
    }

    /// The plan `planID`, which must be the working plan of its series.
    func requireWorkingPlan(_ planID: MealPlanID) async throws -> MealPlan {
        guard let plan = try await repositories.mealPlans.fetch(id: planID) else {
            throw ServiceError.planNotFound(planID)
        }
        let series = try await repositories.mealPlans.fetchSeries(plan.seriesId)
        guard let working = PlanningEngine.workingPlan(in: series, series: plan.seriesId), working.id == planID else {
            throw ServiceError.notWorkingPlan(planID)
        }
        return working
    }

    // MARK: Validation

    /// `PlanValidator` against the current household and library. Always called at use time.
    func validate(_ plan: MealPlan, household: Household) -> ValidationReport {
        PlanValidator.validate(plan, household: household, library: library.safety)
    }

    /// AC-4.2 for a draft: validates it; meals the validator rejects are emptied with
    /// `.removedByValidator` (a planner bug, reported through diagnostics); validates again
    /// and sets every `blockedBySafety` flag from that final report. The result always passes.
    func sanitizedDraft(_ draft: MealPlan, household: Household) throws -> ValidatedPlan {
        var plan = draft
        plan.contentVersion = library.contentVersion
        var report = validate(plan, household: household)
        if !report.passedForEveryone {
            let rejected = report.violatingMealIDs
            context.diagnostics(.validatorRejectedPlannerOutput(planId: plan.id, meals: rejected))
            let rejectedSet = Set(rejected)
            for index in plan.meals.indices where rejectedSet.contains(plan.meals[index].id) {
                plan.meals[index] = PlanningEngine.emptied(plan.meals[index], reason: .removedByValidator)
            }
            report = validate(plan, household: household)
        }
        guard report.passedForEveryone else {
            // Unreachable: empty meals have nothing to check. Fail closed anyway.
            throw ServiceError.validationFailed(violatingMeals: report.violatingMealIDs)
        }
        let checked = plan
        let finalReport = report
        let flagged = try mappingDomainErrors { try PlanLifecycle.applySafetyRecheck(checked, validation: finalReport) }
        return ValidatedPlan(plan: flagged, report: finalReport)
    }

    static func emptied(_ meal: PlannedMeal, reason: EmptyMealReason) -> PlannedMeal {
        var copy = meal
        copy.recipeId = nil
        copy.emptyReason = reason
        copy.reasons = []
        copy.locked = false
        copy.blockedBySafety = false
        return copy
    }

    // MARK: Fixing unsafe meals

    /// Replaces each meal in `mealIDs` with a different safe recipe (a re-roll under `clearance`),
    /// or empties it with `.noSafeRecipe` when none exists. Safety beats a lock: a locked meal
    /// is unlocked and gets `.lockedMealNoLongerSafe` first (as regenerate does, T11).
    func replanMeals(
        _ mealIDs: [PlannedMealID], in plan: MealPlan, household: Household, clearance: SafetyClearance,
        signals: PlannerSignals, now: Date
    ) throws -> MealPlan {
        var result = plan
        for mealID in mealIDs {
            guard let index = result.meals.firstIndex(where: { $0.id == mealID }) else { continue }
            let wasLocked = result.meals[index].locked
            result.meals[index].locked = false
            let current = result
            let replacement = try mappingDomainErrors {
                try WeekPlanner.reroll(
                    mealID, in: current, reason: nil, clearance: clearance, household: household,
                    library: library.planner, signals: signals, now: now, timeZone: timeZone)
            }
            guard var meal = replacement else {
                var empty = PlanningEngine.emptied(result.meals[index], reason: .noSafeRecipe)
                if wasLocked {
                    empty.reasons = [.lockedMealNoLongerSafe]
                }
                result.meals[index] = empty
                continue
            }
            if wasLocked {
                var reasons: [ExplanationReason] = [.lockedMealNoLongerSafe]
                reasons.append(contentsOf: meal.reasons.prefix(1))
                meal.reasons = reasons
            }
            result.meals[index] = meal
        }
        return result
    }

    /// Validates `draft`; re-plans the meals that fail under `clearance`; then sanitises.
    func fixedDraft(
        _ draft: MealPlan, household: Household, clearance: SafetyClearance, now: Date
    ) async throws -> ValidatedPlan {
        let report = validate(draft, household: household)
        guard !report.passedForEveryone else {
            return try sanitizedDraft(draft, household: household)
        }
        let scoring = try await signals(now: now)
        let replanned = try replanMeals(
            report.violatingMealIDs, in: draft, household: household, clearance: clearance, signals: scoring,
            now: now)
        return try sanitizedDraft(replanned, household: household)
    }

    // MARK: R1

    /// R1 (plan V1; AC-3.5): re-validates every open draft **and** every active approved plan
    /// against `household`'s current hard rules and the current library, at call time.
    ///
    /// - Approved plans: unsafe meals are flagged `blockedBySafety` (flags of meals that are
    ///   safe again are cleared). The approval stays (the flag is not in the content hash), and
    ///   when no draft revision is open a fixed draft revision is proposed.
    /// - Drafts (open or just proposed): unsafe meals are re-planned under a fresh clearance;
    ///   whatever still fails is emptied. If the gate refuses, the unsafe meals are only
    ///   flagged and `planningRefusal` is set (approval re-validates and refuses anyway).
    /// - Every re-checked plan is stamped with the current `contentVersion`.
    ///
    /// All changed plans are saved in one atomic `save(_:)`.
    func recheckOpenPlans(household: Household, now: Date) async throws -> SafetyRecheckOutcome {
        let all = try await repositories.mealPlans.fetchAll()
        var outcome = SafetyRecheckOutcome()
        let gate = SafetyGate.evaluate(household, now: now, timeZone: timeZone)

        var seriesOrder: [PlanSeriesID] = []
        var seen = Set<PlanSeriesID>()
        for plan in all where (plan.status == .draft || plan.status == .approved) && seen.insert(plan.seriesId).inserted {
            seriesOrder.append(plan.seriesId)
        }

        var toSave: [MealPlan] = []
        for series in seriesOrder {
            let inSeries = all.filter { $0.seriesId == series }
            var draft = PlanningEngine.openDraft(in: inSeries)
            var proposed = false

            if let approved = PlanLifecycle.activeApprovedPlan(in: inSeries, series: series) {
                let report = validate(approved, household: household)
                var rechecked = try mappingDomainErrors {
                    try PlanLifecycle.applySafetyRecheck(approved, validation: report)
                }
                rechecked.contentVersion = library.contentVersion
                if rechecked != approved {
                    toSave.append(rechecked)
                }
                if !report.passedForEveryone {
                    outcome.blockedMeals.append(contentsOf: report.violatingMealIDs)
                    if draft == nil {
                        switch gate {
                        case .success:
                            let id = newPlanID()
                            let base = rechecked
                            draft = try mappingDomainErrors { try PlanLifecycle.makeRevision(of: base, id: id, now: now) }
                            proposed = true
                        case .failure(let refusal):
                            outcome.planningRefusal = refusal
                        }
                    }
                }
            }

            guard let original = draft else { continue }
            let report = validate(original, household: household)
            var updated: MealPlan
            if report.passedForEveryone {
                updated = try mappingDomainErrors { try PlanLifecycle.applySafetyRecheck(original, validation: report) }
                updated.contentVersion = library.contentVersion
            } else {
                switch gate {
                case .success(let clearance):
                    updated = try await fixedDraft(original, household: household, clearance: clearance, now: now).plan
                    if proposed {
                        outcome.proposedDrafts.append(updated.id)
                    } else {
                        outcome.fixedDrafts.append(updated.id)
                    }
                case .failure(let refusal):
                    updated = try mappingDomainErrors {
                        try PlanLifecycle.applySafetyRecheck(original, validation: report)
                    }
                    updated.contentVersion = library.contentVersion
                    outcome.planningRefusal = refusal
                }
            }
            if proposed || updated != original {
                toSave.append(updated)
            }
        }

        if !toSave.isEmpty {
            try await repositories.mealPlans.save(toSave)
        }
        return outcome
    }
}
