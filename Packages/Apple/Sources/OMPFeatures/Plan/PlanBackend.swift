import Foundation
import OMPDomain
import OMPServices

/// What the Plan screens need from the use-case services (task T23). The live implementation
/// wraps `PlanService` and `LunchboxService`; tests use a fake. Every method that changes a plan
/// goes through the services, which run the safety gate and the independent validator
/// themselves: the screens never plan, edit or approve on their own (ADR 0007, ADR 0008).
///
/// Results are plain `MealPlan` values: the validator report stays inside the service, which
/// re-validates at call time anyway.
public protocol PlanBackend: Sendable {
    func currentSeriesID() async throws -> PlanSeriesID?
    /// The open draft of `series`, else its active approved plan.
    func workingPlan(series: PlanSeriesID) async throws -> MealPlan?
    /// The effectively approved plan, even while a draft revision is pending (A6).
    func activeApprovedPlan(series: PlanSeriesID) async throws -> MealPlan?
    /// Approved plan against its pending draft revision, or nil.
    func pendingDiff(series: PlanSeriesID) async throws -> PlanDiff?

    func generateWeek() async throws -> MealPlan
    /// Regenerates the working plan; `keepingLocked` keeps locked meals that are still safe (AC-8.3).
    func regenerate(_ planID: MealPlanID, keepingLocked: Bool) async throws -> MealPlan
    func alternatives(for mealID: PlannedMealID, in planID: MealPlanID, reason: RerollReason?) async throws
        -> [MealAlternative]
    func swap(_ mealID: PlannedMealID, in planID: MealPlanID, to recipeID: RecipeID) async throws -> MealPlan
    func reroll(_ mealID: PlannedMealID, in planID: MealPlanID, reason: RerollReason?) async throws -> MealPlan
    func setLocked(_ locked: Bool, meal mealID: PlannedMealID, in planID: MealPlanID) async throws -> MealPlan
    func discard(_ planID: MealPlanID) async throws

    /// Approves `planID`. The `UserConfirmation` can only be made by the approval controls
    /// (`Approval*.swift`), so nothing else in the app can call this successfully.
    func approve(_ planID: MealPlanID, confirmation: UserConfirmation) async throws -> MealPlan

    /// Whether the lunchbox card (C-104) may show for a meal in `slot` now (AC-7.1, AC-7.3);
    /// when it returns true the card is recorded as shown.
    func lunchboxPromptDue(for slot: MealSlot) async throws -> Bool
    func answerLunchboxPrompt(_ answer: LunchboxPromptAnswer) async throws
    /// AC-7.2. Returns the gate refusal when lunchboxes could not be added yet.
    func setUpSchoolLunches(children: [MemberID], days: Set<Weekday>) async throws -> GateRefusal?

    /// Recipe content for display only (it never feeds a safety decision).
    func recipe(_ id: RecipeID) -> Recipe?
    func ingredientName(_ id: IngredientID) -> String?
    /// The commands in a spoken transcript; "approve it" yields `.openApprovalSheet` only.
    func spokenCommands(in transcript: String) -> [SpokenCommand]
}

/// The services as the Plan screens use them.
public final class LivePlanBackend: PlanBackend {
    private let plans: PlanService
    private let lunchbox: LunchboxService
    private let library: PlanningLibrary

    public init(context: ServiceContext) {
        self.plans = PlanService(context: context)
        self.lunchbox = LunchboxService(context: context)
        self.library = context.library
    }

    public func currentSeriesID() async throws -> PlanSeriesID? {
        try await plans.currentSeriesID()
    }

    public func workingPlan(series: PlanSeriesID) async throws -> MealPlan? {
        try await plans.workingPlan(series: series)
    }

    public func activeApprovedPlan(series: PlanSeriesID) async throws -> MealPlan? {
        try await plans.activeApprovedPlan(series: series)
    }

    public func pendingDiff(series: PlanSeriesID) async throws -> PlanDiff? {
        try await plans.pendingDiff(series: series)
    }

    public func generateWeek() async throws -> MealPlan {
        try await plans.generateWeek().plan
    }

    public func regenerate(_ planID: MealPlanID, keepingLocked: Bool) async throws -> MealPlan {
        try await plans.regenerate(planID, keepingLocked: keepingLocked).plan
    }

    public func alternatives(for mealID: PlannedMealID, in planID: MealPlanID, reason: RerollReason?) async throws
        -> [MealAlternative]
    {
        try await plans.alternatives(for: mealID, in: planID, reason: reason, limit: 3)
    }

    public func swap(_ mealID: PlannedMealID, in planID: MealPlanID, to recipeID: RecipeID) async throws -> MealPlan {
        try await plans.swap(mealID, in: planID, to: recipeID).plan
    }

    public func reroll(_ mealID: PlannedMealID, in planID: MealPlanID, reason: RerollReason?) async throws
        -> MealPlan
    {
        try await plans.reroll(mealID, in: planID, reason: reason).plan
    }

    public func setLocked(_ locked: Bool, meal mealID: PlannedMealID, in planID: MealPlanID) async throws -> MealPlan {
        try await plans.setLocked(locked, meal: mealID, in: planID).plan
    }

    public func discard(_ planID: MealPlanID) async throws {
        try await plans.discard(planID)
    }

    public func approve(_ planID: MealPlanID, confirmation: UserConfirmation) async throws -> MealPlan {
        try await plans.approve(planID, confirmation: confirmation).approved
    }

    public func lunchboxPromptDue(for slot: MealSlot) async throws -> Bool {
        try await lunchbox.promptForOpenedSlot(slot) != nil
    }

    public func answerLunchboxPrompt(_ answer: LunchboxPromptAnswer) async throws {
        try await lunchbox.answerPrompt(answer)
    }

    public func setUpSchoolLunches(children: [MemberID], days: Set<Weekday>) async throws -> GateRefusal? {
        try await lunchbox.setUpSchoolLunches(children: children, days: days).planningRefusal
    }

    public func recipe(_ id: RecipeID) -> Recipe? {
        library.recipesByID[id]
    }

    public func ingredientName(_ id: IngredientID) -> String? {
        library.ingredientsByID[id]?.name
    }

    public func spokenCommands(in transcript: String) -> [SpokenCommand] {
        SpokenCommandParser(resolver: library.resolver).parse(transcript).commands
    }
}
