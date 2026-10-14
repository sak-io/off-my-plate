import Foundation
import OMPDomain
import OMPServices
import Testing

@testable import OMPFeatures

// MARK: Fakes and fixtures

/// A scripted `PlanBackend`. Tests run on the main actor one at a time, so the unchecked
/// Sendable conformance is safe here.
private final class FakePlanBackend: PlanBackend, @unchecked Sendable {
    var plans: [MealPlan]
    var approveError: (any Error)?
    var generateError: (any Error)?
    var alternativeList: [MealAlternative] = []
    var promptDue = false

    private(set) var approveCalls = 0
    private(set) var regenerateCalls = 0
    private(set) var generateCalls = 0
    private(set) var swapCalls: [RecipeID] = []
    private(set) var discardCalls = 0
    private(set) var lockCalls: [(PlannedMealID, Bool)] = []

    init(plans: [MealPlan]) {
        self.plans = plans
    }

    func currentSeriesID() async throws -> PlanSeriesID? { plans.last?.seriesId }

    func workingPlan(series: PlanSeriesID) async throws -> MealPlan? {
        plans.last { $0.status == .draft } ?? plans.last { $0.status == .approved }
    }

    func activeApprovedPlan(series: PlanSeriesID) async throws -> MealPlan? {
        plans.last { $0.status == .approved }
    }

    func pendingDiff(series: PlanSeriesID) async throws -> PlanDiff? {
        guard let approved = plans.last(where: { $0.status == .approved }),
            let draft = plans.last(where: { $0.status == .draft }), draft.basedOn == approved.id
        else { return nil }
        return PlanDiff(from: approved, to: draft)
    }

    func generateWeek() async throws -> MealPlan {
        generateCalls += 1
        if let generateError { throw generateError }
        let plan = makePlan(id: "generated", recipes: ["r0", "r1"])
        plans.append(plan)
        return plan
    }

    func regenerate(_ planID: MealPlanID) async throws -> MealPlan {
        regenerateCalls += 1
        return plans.last { $0.id == planID } ?? plans[0]
    }

    func alternatives(for mealID: PlannedMealID, in planID: MealPlanID, reason: RerollReason?) async throws
        -> [MealAlternative]
    { alternativeList }

    func swap(_ mealID: PlannedMealID, in planID: MealPlanID, to recipeID: RecipeID) async throws -> MealPlan {
        swapCalls.append(recipeID)
        return plans[0]
    }

    func reroll(_ mealID: PlannedMealID, in planID: MealPlanID, reason: RerollReason?) async throws -> MealPlan {
        throw ServiceError.noOtherSafeRecipe(mealID)
    }

    func setLocked(_ locked: Bool, meal mealID: PlannedMealID, in planID: MealPlanID) async throws -> MealPlan {
        lockCalls.append((mealID, locked))
        return plans[0]
    }

    func discard(_ planID: MealPlanID) async throws {
        discardCalls += 1
        plans.removeAll { $0.id == planID }
    }

    func approve(_ planID: MealPlanID, confirmation: UserConfirmation) async throws -> MealPlan {
        approveCalls += 1
        if let approveError { throw approveError }
        guard let draft = plans.first(where: { $0.id == planID }) else { throw ServiceError.planNotFound(planID) }
        let approved = makePlan(
            id: draft.id.rawValue, status: .approved, basedOn: draft.basedOn, revision: draft.revision,
            recipes: draft.meals.map { $0.recipeId?.rawValue })
        plans = plans.map { plan in
            if plan.id == planID { return approved }
            if plan.status == .approved {
                return makePlan(
                    id: plan.id.rawValue, status: .superseded, revision: plan.revision,
                    recipes: plan.meals.map { $0.recipeId?.rawValue })
            }
            return plan
        }
        return approved
    }

    func lunchboxPromptDue(for slot: MealSlot) async throws -> Bool { promptDue }
    func answerLunchboxPrompt(_ answer: LunchboxPromptAnswer) async throws {}
    func setUpSchoolLunches(children: [MemberID], days: Set<Weekday>) async throws -> GateRefusal? { nil }
    func recipe(_ id: RecipeID) -> Recipe? { nil }
    func ingredientName(_ id: IngredientID) -> String? { nil }

    func spokenCommands(in transcript: String) -> [SpokenCommand] {
        transcript.lowercased().contains("approve") ? [.openApprovalSheet] : []
    }
}

private let series = PlanSeriesID("series-1")
private let weekStart = LocalDate(year: 2026, month: 10, day: 12)!  // fixtureNow's day

/// A plan with one dinner a day from `weekStart`; a nil recipe is an empty slot.
private func makePlan(
    id: String, status: PlanStatus = .draft, basedOn: MealPlanID? = nil, revision: Int = 1,
    recipes: [String?], locked: Set<Int> = []
) -> MealPlan {
    let meals = recipes.enumerated().map { index, recipe in
        PlannedMeal(
            id: PlannedMealID("m\(index)"), date: weekStart.adding(days: index), slot: .dinner,
            recipeId: recipe.map { RecipeID($0) }, emptyReason: recipe == nil ? .noSafeRecipe : nil,
            locked: locked.contains(index), servings: [])
    }
    return MealPlan(
        id: MealPlanID(id), seriesId: series, revision: revision, basedOn: basedOn, weekStart: weekStart,
        status: status, meals: meals,
        approval: status == .approved ? PlanApproval(approvedAt: fixtureNow, contentHash: "h") : nil,
        contentVersion: "test", createdAt: fixtureNow)
}

@MainActor
private func makeViewModel(
    _ backend: FakePlanBackend, members: [Member] = [member(.adult, 1, .confirmedNone)]
) async -> (PlanViewModel, AppModel) {
    let clock = FixedClock(now: fixtureNow, timeZone: utc)
    let repositories = Repositories.inMemory()
    try? await repositories.household.replace(with: household(members))
    let app = AppModel(repositories: repositories, clock: clock, planBackend: backend)
    await app.refresh()
    return (PlanViewModel(backend: backend, app: app, clock: clock), app)
}

// MARK: Tests

@Suite("PlanViewModel")
@MainActor
struct PlanViewModelTests {
    @Test("No plan yet shows the empty state; Make a plan generates and shows a draft")
    func emptyThenGenerate() async {
        let backend = FakePlanBackend(plans: [])
        let (model, _) = await makeViewModel(backend)
        await model.load()
        #expect(model.phase == .empty)
        await model.makePlan()
        #expect(backend.generateCalls == 1)
        #expect(model.phase == .loaded)
        #expect(model.status == .draft)
        #expect(model.isFirstDraft)
    }

    @Test("A failed generation keeps the empty state with the C-052 error and retries")
    func generationFails() async {
        let backend = FakePlanBackend(plans: [])
        backend.generateError = ServiceError.noHousehold
        let (model, _) = await makeViewModel(backend)
        await model.load()
        await model.makePlan()
        #expect(model.phase == .empty)
        #expect(model.errorMessage == PlanCopy.error)
        backend.generateError = nil
        await model.retry()
        #expect(model.phase == .loaded)
        #expect(model.errorMessage == nil)
    }

    @Test("Approving a draft calls the service with a confirmation and shows the approved status")
    func approveWeek() async {
        let backend = FakePlanBackend(plans: [makePlan(id: "p1", recipes: ["r0", "r1"])])
        let (model, _) = await makeViewModel(backend)
        await model.load()
        #expect(model.isFirstDraft)
        await model.approve(confirmation: UserConfirmation())
        #expect(backend.approveCalls == 1)
        #expect(model.plan?.status == .approved)
        #expect(!model.isDraft)
        #expect(model.toast == PlanCopy.weekApproved)
        if case .approved = model.status {} else { Issue.record("status is not approved: \(String(describing: model.status))") }
    }

    @Test("Approving anything but a draft does nothing")
    func approveApprovedPlan() async {
        let backend = FakePlanBackend(plans: [makePlan(id: "p1", status: .approved, recipes: ["r0"])])
        let (model, _) = await makeViewModel(backend)
        await model.load()
        await model.approve(confirmation: UserConfirmation())
        #expect(backend.approveCalls == 0)
    }

    @Test("Spoken 'approve it' opens the approval sheet and approves nothing")
    func voiceOpensSheetOnly() async {
        let backend = FakePlanBackend(plans: [makePlan(id: "p1", recipes: ["r0"])])
        let (model, _) = await makeViewModel(backend)
        await model.load()
        #expect(model.handleSpokenTranscript("approve it"))
        #expect(model.sheet == .approval)
        #expect(backend.approveCalls == 0)
        #expect(model.isDraft)
        #expect(!model.handleSpokenTranscript("what's for dinner"))
    }

    @Test("Spoken approve does nothing when there is no draft or safety blocks planning")
    func voiceNeedsDraftAndClearGate() async {
        let approvedOnly = FakePlanBackend(plans: [makePlan(id: "p1", status: .approved, recipes: ["r0"])])
        let (approvedModel, _) = await makeViewModel(approvedOnly)
        await approvedModel.load()
        #expect(!approvedModel.handleSpokenTranscript("approve it"))
        #expect(approvedModel.sheet == nil)

        let draft = FakePlanBackend(plans: [makePlan(id: "p1", recipes: ["r0"])])
        let (blocked, _) = await makeViewModel(
            draft, members: [member(.adult, 1, .confirmedNone), member(.child, 1, .unasked)])
        await blocked.load()
        #expect(blocked.isBlocked)
        #expect(!blocked.handleSpokenTranscript("approve it"))
        #expect(blocked.sheet == nil)
        #expect(draft.approveCalls == 0)
    }

    @Test("Mark cooked is not offered on a draft, and is offered on an approved plan for past days only")
    func markCookedOnlyWhenApproved() async {
        let draftBackend = FakePlanBackend(plans: [makePlan(id: "p1", recipes: ["r0", "r1"])])
        let (draftModel, _) = await makeViewModel(draftBackend)
        await draftModel.load()
        let todayMeal = draftModel.plan!.meals[0]
        #expect(draftModel.cookableMeal(for: todayMeal) == nil)

        let approvedBackend = FakePlanBackend(plans: [makePlan(id: "p1", status: .approved, recipes: ["r0", "r1"])])
        let (approvedModel, _) = await makeViewModel(approvedBackend)
        await approvedModel.load()
        let today = approvedModel.plan!.meals[0]
        let tomorrow = approvedModel.plan!.meals[1]
        #expect(approvedModel.cookableMeal(for: today) != nil)
        #expect(approvedModel.cookableMeal(for: tomorrow) == nil)
    }

    @Test("Mark cooked is not offered for an empty slot")
    func noMarkCookedWhenEmpty() async {
        let backend = FakePlanBackend(plans: [makePlan(id: "p1", status: .approved, recipes: [nil])])
        let (model, _) = await makeViewModel(backend)
        await model.load()
        #expect(model.cookableMeal(for: model.plan!.meals[0]) == nil)
    }

    @Test("Editing an approved plan shows pending changes, the change count and the approved meal to cook")
    func pendingRevision() async {
        let approved = makePlan(id: "a1", status: .approved, recipes: ["r0", "r1"])
        let revision = makePlan(id: "d2", basedOn: approved.id, revision: 2, recipes: ["r9", "r1"])
        let backend = FakePlanBackend(plans: [approved, revision])
        let (model, _) = await makeViewModel(backend)
        await model.load()
        #expect(model.status == .pendingChanges)
        #expect(model.hasPendingChanges)
        #expect(!model.isFirstDraft)
        #expect(model.changeCount == 1)
        let changed = model.plan!.meals[0]
        #expect(model.change(for: changed) != nil)
        #expect(model.change(for: model.plan!.meals[1]) == nil)
        // Mark cooked acts on the approved meal, not the proposed one.
        #expect(model.cookableMeal(for: changed)?.recipeId == RecipeID("r0"))
        model.requestApprovalSheet()
        #expect(model.sheet == .approval)
    }

    @Test("Approving a revision shows the 'changes approved' toast")
    func approveRevision() async {
        let approved = makePlan(id: "a1", status: .approved, recipes: ["r0"])
        let revision = makePlan(id: "d2", basedOn: approved.id, revision: 2, recipes: ["r9"])
        let backend = FakePlanBackend(plans: [approved, revision])
        let (model, _) = await makeViewModel(backend)
        await model.load()
        model.requestApprovalSheet()
        await model.approve(confirmation: UserConfirmation())
        #expect(model.toast == PlanCopy.changesApproved)
        #expect(model.sheet == nil)
        #expect(!model.hasPendingChanges)
    }

    @Test("Discarding a revision leaves the approved plan")
    func discardRevision() async {
        let approved = makePlan(id: "a1", status: .approved, recipes: ["r0"])
        let revision = makePlan(id: "d2", basedOn: approved.id, revision: 2, recipes: ["r9"])
        let backend = FakePlanBackend(plans: [approved, revision])
        let (model, _) = await makeViewModel(backend)
        await model.load()
        await model.discardChanges()
        #expect(backend.discardCalls == 1)
        #expect(model.plan?.id == approved.id)
        #expect(model.status != .pendingChanges)
    }

    @Test("A first draft cannot be discarded through the revision control")
    func discardNeedsRevision() async {
        let backend = FakePlanBackend(plans: [makePlan(id: "p1", recipes: ["r0"])])
        let (model, _) = await makeViewModel(backend)
        await model.load()
        await model.discardChanges()
        model.requestDiscard()
        #expect(backend.discardCalls == 0)
        #expect(!model.isConfirmingDiscard)
    }

    @Test("An empty slot offers its reason, and approval stays allowed")
    func emptySlot() async {
        let backend = FakePlanBackend(plans: [makePlan(id: "p1", recipes: ["r0", nil])])
        let (model, _) = await makeViewModel(backend)
        await model.load()
        let empty = model.plan!.meals[1]
        #expect(empty.isEmpty)
        #expect(!model.expandedWhy.contains(empty.id))
        model.toggleWhy(empty.id)
        #expect(model.expandedWhy.contains(empty.id))
        model.toggleWhy(empty.id)
        #expect(!model.expandedWhy.contains(empty.id))
        #expect(model.canOpenApproval)
        #expect(model.mealCount == 1)
    }

    @Test("Regenerate asks the service to regenerate the working plan")
    func regenerate() async {
        let backend = FakePlanBackend(plans: [makePlan(id: "p1", recipes: ["r0", "r1"], locked: [0])])
        let (model, _) = await makeViewModel(backend)
        await model.load()
        await model.regenerate()
        #expect(backend.regenerateCalls == 1)
        #expect(model.plan?.meals[0].locked == true)
        #expect(!model.isRegenerating)
    }

    @Test("Safety blocking disables Regenerate, Swap and approval, with C-081 for the person")
    func blockedBySafety() async {
        let backend = FakePlanBackend(plans: [makePlan(id: "p1", recipes: ["r0"])])
        let (model, _) = await makeViewModel(
            backend, members: [member(.adult, 1, .confirmedNone), member(.child, 1, .unasked)])
        await model.load()
        #expect(model.isBlocked)
        #expect(model.blockingName == "Child 1")
        await model.regenerate()
        #expect(backend.regenerateCalls == 0)
        await model.openSwap(model.plan!.meals[0].id)
        #expect(model.sheet == nil)
        #expect(model.alert == .blocked(name: "Child 1"))
        #expect(!model.canOpenApproval)
    }

    @Test("A validator failure at approval shows C-071, then regenerates the affected meals")
    func validatorFailure() async {
        let backend = FakePlanBackend(plans: [makePlan(id: "p1", recipes: ["r0"])])
        backend.approveError = ServiceError.validationFailed(violatingMeals: [PlannedMealID("m0")])
        let (model, _) = await makeViewModel(backend)
        await model.load()
        await model.approve(confirmation: UserConfirmation())
        #expect(model.alert == .validatorFailed)
        #expect(model.plan?.status == .draft)
        await model.acknowledgeAlert()
        #expect(model.alert == nil)
        #expect(backend.regenerateCalls == 1)
    }

    @Test("A validator failure inside the approval sheet is shown in the sheet")
    func validatorFailureInSheet() async {
        let backend = FakePlanBackend(plans: [makePlan(id: "p1", recipes: ["r0"])])
        backend.approveError = ServiceError.validationFailed(violatingMeals: [PlannedMealID("m0")])
        let (model, _) = await makeViewModel(backend)
        await model.load()
        model.requestApprovalSheet()
        await model.approve(confirmation: UserConfirmation())
        #expect(model.validationFailed)
        #expect(model.alert == nil)
        #expect(model.sheet == .approval)
        await model.acknowledgeValidatorFailure()
        #expect(!model.validationFailed)
        #expect(model.sheet == nil)
        #expect(backend.regenerateCalls == 1)
    }

    @Test("Any other approval failure shows the save error and leaves the draft")
    func saveFailure() async {
        let backend = FakePlanBackend(plans: [makePlan(id: "p1", recipes: ["r0"])])
        backend.approveError = ServiceError.planNotFound(MealPlanID("p1"))
        let (model, _) = await makeViewModel(backend)
        await model.load()
        await model.approve(confirmation: UserConfirmation())
        #expect(model.errorMessage == PlanCopy.saveFailed)
        #expect(model.isDraft)
    }

    @Test("Swap lists alternatives, applies the chosen one and tells an approved plan it needs approval")
    func swapFlow() async {
        let backend = FakePlanBackend(plans: [makePlan(id: "a1", status: .approved, recipes: ["r0"])])
        backend.alternativeList = [MealAlternative(recipeId: RecipeID("r5"), reasons: [.goodForLunchboxes])]
        let (model, _) = await makeViewModel(backend)
        await model.load()
        let meal = model.plan!.meals[0]
        await model.openSwap(meal.id)
        #expect(model.sheet == .swap(meal.id))
        guard case .options(let options) = model.swapState else {
            Issue.record("No options: \(model.swapState)")
            return
        }
        #expect(options.map(\.recipeID) == [RecipeID("r5")])
        #expect(options.first?.reason == PlanCopy.reason(.goodForLunchboxes, ingredientName: { _ in nil }))
        await model.choose(options[0])
        #expect(backend.swapCalls == [RecipeID("r5")])
        #expect(model.sheet == nil)
        #expect(model.toast == PlanCopy.swappedNeedsApproval)
    }

    @Test("Swap with no safe alternative shows C-067")
    func swapEmpty() async {
        let backend = FakePlanBackend(plans: [makePlan(id: "p1", recipes: ["r0"])])
        let (model, _) = await makeViewModel(backend)
        await model.load()
        await model.openSwap(model.plan!.meals[0].id)
        #expect(model.swapState == .empty)
        await model.pickForMe()
        #expect(model.swapState == .empty)
        #expect(model.sheet == .swap(model.plan!.meals[0].id))
    }

    @Test("Locking a meal goes through the service")
    func lock() async {
        let backend = FakePlanBackend(plans: [makePlan(id: "p1", recipes: ["r0"])])
        let (model, _) = await makeViewModel(backend)
        await model.load()
        await model.toggleLock(model.plan!.meals[0])
        #expect(backend.lockCalls.count == 1)
        #expect(backend.lockCalls[0].1 == true)
    }

    @Test("Days are grouped in plan order with slots in meal order")
    func daysGrouping() async {
        let backend = FakePlanBackend(plans: [makePlan(id: "p1", recipes: ["r0", "r1", "r2"])])
        let (model, _) = await makeViewModel(backend)
        await model.load()
        #expect(model.days.map(\.date) == [weekStart, weekStart.adding(days: 1), weekStart.adding(days: 2)])
        #expect(model.days.allSatisfy { $0.meals.count == 1 })
    }

    @Test("The first-plan banner shows on a first draft until dismissed and never on an approved plan")
    func banner() async {
        let backend = FakePlanBackend(plans: [makePlan(id: "p1", recipes: ["r0"])])
        let (model, _) = await makeViewModel(backend)
        await model.load()
        #expect(model.showsFirstPlanBanner)
        model.bannerDismissed = true
        #expect(!model.showsFirstPlanBanner)

        let approvedBackend = FakePlanBackend(plans: [makePlan(id: "a1", status: .approved, recipes: ["r0"])])
        let (approved, _) = await makeViewModel(approvedBackend)
        await approved.load()
        #expect(!approved.showsFirstPlanBanner)
    }

    @Test("The lunchbox card appears only for a lunch the service says is due")
    func lunchboxCard() async {
        let lunch = PlannedMeal(
            id: PlannedMealID("l0"), date: weekStart, slot: .lunch, recipeId: RecipeID("r0"), servings: [])
        let dinner = PlannedMeal(
            id: PlannedMealID("d0"), date: weekStart, slot: .dinner, recipeId: RecipeID("r1"), servings: [])
        let backend = FakePlanBackend(plans: [makePlan(id: "p1", recipes: ["r0"])])
        backend.promptDue = true
        let (model, _) = await makeViewModel(backend)
        await model.load()
        await model.mealOpened(dinner)
        #expect(!model.lunchboxCardVisible)
        await model.mealOpened(lunch)
        #expect(model.lunchboxCardVisible)
        await model.answerLunchbox(.yes)
        #expect(!model.lunchboxCardVisible)
        #expect(model.sheet == .schoolLunches)
    }

    @Test("Without a backend the Plan tab reports a load failure instead of crashing")
    func noBackend() async {
        let clock = FixedClock(now: fixtureNow, timeZone: utc)
        let app = AppModel(repositories: .inMemory(), clock: clock)
        let model = PlanViewModel(backend: nil, app: app, clock: clock)
        await model.load()
        #expect(model.phase == .failed)
    }
}
