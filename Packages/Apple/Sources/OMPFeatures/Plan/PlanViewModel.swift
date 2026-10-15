import Foundation
import Observation
import OMPDomain
import OMPServices

/// A sheet the Plan tab presents.
public enum PlanSheet: Hashable, Identifiable, Sendable {
    /// S-13: the approval sheet (the diff of a pending revision, or the whole week).
    case approval
    /// S-12: swap this meal.
    case swap(PlannedMealID)
    /// S-14: school lunches.
    case schoolLunches
    /// S-15: the cooked sheet of an approved plan's meal (task T24).
    case cooked(plan: MealPlanID, meal: PlannedMealID)

    public var id: String {
        switch self {
        case .approval: return "approval"
        case .swap(let meal): return "swap:\(meal.rawValue)"
        case .schoolLunches: return "schoolLunches"
        case .cooked(let plan, let meal): return "cooked:\(plan.rawValue):\(meal.rawValue)"
        }
    }
}

/// An alert on the Plan tab.
public enum PlanAlert: Hashable, Sendable {
    /// C-071: the independent safety check failed at approval; affected meals are replaced.
    case validatorFailed
    /// C-081: the safety gate refuses; `name` is who must answer first.
    case blocked(name: String)
}

/// What the status label at the top of S-10 says.
public enum PlanStatusKind: Hashable, Sendable {
    case draft
    case approved(Date)
    case pendingChanges
}

/// One day of the plan, meals in slot order.
public struct PlanDay: Identifiable, Hashable, Sendable {
    public let date: LocalDate
    public let meals: [PlannedMeal]
    public var id: String { date.isoString }
}

/// One alternative offered in the swap sheet (S-12).
public struct SwapOption: Identifiable, Hashable, Sendable {
    public let recipeID: RecipeID
    public let title: String
    public let minutes: Int?
    public let reason: String?
    public var id: String { recipeID.rawValue }
}

/// Loading state of the swap sheet's list.
public enum SwapState: Hashable, Sendable {
    case loading
    case options([SwapOption])
    /// C-067: no other safe recipe.
    case empty
    case failed
}

/// The Plan tab's state and actions (task T23; screens S-10 to S-14).
///
/// Every change goes through the `PlanBackend` (the services), which evaluate the safety gate
/// and run the independent validator at call time. This type never plans, edits or approves
/// anything itself, and it cannot approve without a `UserConfirmation`, which only
/// `Approval*.swift` creates from a button tap (AC-5.6). Spoken "approve it" can only call
/// `handleSpokenTranscript`, which opens the sheet.
@MainActor
@Observable
public final class PlanViewModel {
    public enum Phase: Hashable, Sendable {
        case loading
        /// No plan yet (C-063).
        case empty
        case loaded
        /// Loading or generating failed (C-052).
        case failed
    }

    private let backend: (any PlanBackend)?
    private let app: AppModel
    private let clock: any DomainClock

    public private(set) var phase: Phase = .loading
    /// The plan on screen: the open draft, else the active approved plan.
    public private(set) var plan: MealPlan?
    /// The plan the shopping list and Mark cooked use; nil while the only plan is a first draft.
    public private(set) var approvedPlan: MealPlan?
    /// The pending revision's diff, or nil.
    public private(set) var diff: PlanDiff?
    /// An operation is running: actions are disabled and the list shows placeholders.
    public private(set) var isBusy = false
    /// Regenerate is running: only unlocked rows show placeholders.
    public private(set) var isRegenerating = false
    /// C-095 inline card text, or nil.
    public private(set) var errorMessage: String?
    public private(set) var expandedWhy: Set<PlannedMealID> = []
    public private(set) var swapState: SwapState = .loading
    public private(set) var swapMealID: PlannedMealID?
    public private(set) var lunchboxCardVisible = false
    /// The independent safety check failed while the approval sheet was open (S-13, C-071).
    public private(set) var validationFailed = false

    public var swapReason: RerollReason?
    public var sheet: PlanSheet?
    public var alert: PlanAlert?
    public var toast: String?
    public var bannerDismissed = false
    public var isConfirmingRegenerate = false
    public var isConfirmingDiscard = false
    /// Called after the cooked sheet (S-15) was requested for an approved meal (plan id, meal
    /// id). Optional extra hook; the sheet itself is opened by `requestMarkCooked`.
    public var onMarkCooked: (@MainActor (MealPlanID, PlannedMealID) -> Void)?

    public init(backend: (any PlanBackend)?, app: AppModel, clock: any DomainClock) {
        self.backend = backend
        self.app = app
        self.clock = clock
    }

    // MARK: Derived state

    public var gateStatus: GateStatus { app.gateStatus }

    /// Safety blocks making or changing drafts (S-10b): Regenerate, Swap and Approve are off.
    public var isBlocked: Bool { app.gateStatus.blocksPlanning }

    /// Who the safety gate is waiting on first.
    public var blockingName: String {
        let ids: [MemberID]
        switch app.gateStatus {
        case .unanswered(let list), .reconfirmationDue(let list): ids = list
        case .loading, .noHousehold, .clear, .loadFailed: ids = []
        }
        if let id = ids.first, let member = app.household?.member(id) {
            return member.displayName
        }
        return PlanCopy.someone
    }

    public var status: PlanStatusKind? {
        guard let plan else { return nil }
        switch plan.status {
        case .approved:
            return .approved(plan.approval?.approvedAt ?? clock.now)
        case .draft:
            return diff != nil ? .pendingChanges : .draft
        case .superseded, .discarded:
            return nil
        }
    }

    public var isDraft: Bool { plan?.status == .draft }

    /// A first plan that has never been approved (shows "Approve week").
    public var isFirstDraft: Bool { plan?.status == .draft && diff == nil }

    public var hasPendingChanges: Bool { diff != nil }

    /// "{n}" of "Review {n} changes".
    public var changeCount: Int { diff?.listedChanges.count ?? 0 }

    public var showsFirstPlanBanner: Bool { isFirstDraft && plan?.revision == 1 && !bannerDismissed }

    public var days: [PlanDay] {
        guard let plan else { return [] }
        let order: [MealSlot] = [.breakfast, .lunch, .lunchbox, .dinner, .snack]
        return plan.dates.map { date in
            let meals = plan.meals.filter { $0.date == date }.sorted { lhs, rhs in
                let l = order.firstIndex(of: lhs.slot) ?? order.count
                let r = order.firstIndex(of: rhs.slot) ?? order.count
                return l != r ? l < r : lhs.id < rhs.id
            }
            return PlanDay(date: date, meals: meals)
        }.filter { !$0.meals.isEmpty }
    }

    public var mealCount: Int { plan?.meals.filter { !$0.isEmpty }.count ?? 0 }

    public func meal(_ id: PlannedMealID) -> PlannedMeal? { plan?.meal(id) }

    public func title(of meal: PlannedMeal) -> String {
        guard let id = meal.recipeId else { return PlanCopy.noRecipe }
        return backend?.recipe(id)?.title ?? PlanCopy.noRecipe
    }

    public func title(ofRecipe id: RecipeID?) -> String {
        guard let id else { return PlanCopy.noRecipe }
        return backend?.recipe(id)?.title ?? PlanCopy.noRecipe
    }

    public func recipe(of meal: PlannedMeal) -> Recipe? {
        meal.recipeId.flatMap { backend?.recipe($0) }
    }

    /// The first template reason, or nil (AC-4.7).
    public func reasonLine(of meal: PlannedMeal) -> String? {
        guard let backend else { return nil }
        for reason in meal.reasons {
            if let text = PlanCopy.reason(reason, ingredientName: { backend.ingredientName($0) }) {
                return text
            }
        }
        return nil
    }

    public func ingredientNames(of recipe: Recipe) -> [String] {
        recipe.ingredients.compactMap { backend?.ingredientName($0.ingredientId) }
    }

    public func memberName(_ id: MemberID) -> String {
        app.household?.member(id)?.displayName ?? PlanCopy.someone
    }

    /// The listed change at `meal`'s slot in the pending revision, if any.
    public func change(for meal: PlannedMeal) -> PlanDiff.Change? {
        diff?.listedChanges.first { $0.date == meal.date && $0.slot == meal.slot }
    }

    /// The approved meal Mark cooked would act on, or nil when it must not be offered: on a
    /// draft that was never approved, for future days, for cooked, empty or safety-blocked
    /// meals (AC-9.x, US-8). With a pending revision it is the approved counterpart.
    public func cookableMeal(for meal: PlannedMeal) -> PlannedMeal? {
        guard let plan, let approved = approvedPlan else { return nil }
        let counterpart: PlannedMeal?
        if approved.id == plan.id {
            counterpart = meal
        } else {
            counterpart = approved.meals.first { $0.date == meal.date && $0.slot == meal.slot }
        }
        guard let target = counterpart, target.recipeId != nil, target.cooked == nil, !target.blockedBySafety,
            target.date <= clock.today
        else { return nil }
        return target
    }

    /// The meal as cooked, from the approved plan.
    public func isCooked(_ meal: PlannedMeal) -> Bool {
        guard let approved = approvedPlan, let plan else { return false }
        if approved.id == plan.id { return meal.cooked != nil }
        return approved.meals.first { $0.date == meal.date && $0.slot == meal.slot }?.cooked != nil
    }

    /// R1: whether the approved plan has meals a hard-rule change made unsafe (C-083).
    public var hasBlockedMeals: Bool {
        approvedPlan?.meals.contains { $0.blockedBySafety } ?? false
    }

    /// Whether `meal` (or the approved meal it proposes to replace) is flagged unsafe.
    public func isMealBlocked(_ meal: PlannedMeal) -> Bool {
        if meal.blockedBySafety { return true }
        guard let plan, let approved = approvedPlan, approved.id != plan.id else { return false }
        return approved.meals.contains { $0.date == meal.date && $0.slot == meal.slot && $0.blockedBySafety }
    }

    /// "Update plan" (C-083): asks the service to regenerate, which makes a draft revision that
    /// replaces the unsafe meals (locked safe meals stay). The user still approves it.
    public func updatePlan() async {
        guard let backend, let plan, !isBusy, !isBlocked else { return }
        await perform {
            _ = try await backend.regenerate(plan.id, keepingLocked: true)
            try await self.reload()
        }
    }

    /// Whether "Answer now" leads anywhere: the safety cover appears while someone is unasked;
    /// a 180-day re-check has no flow yet (T22), so no button is offered for it.
    public var canAnswerNow: Bool {
        if case .unanswered = app.gateStatus { return true }
        return false
    }

    public func requestMarkCooked(_ meal: PlannedMeal) {
        guard let target = cookableMeal(for: meal), let approved = approvedPlan else { return }
        // Only an approved plan's meal gets here (`cookableMeal`); the service checks again.
        sheet = .cooked(plan: approved.id, meal: target.id)
        onMarkCooked?(approved.id, target.id)
    }

    // MARK: Dates

    public func dayTitle(_ date: LocalDate) -> String {
        format(date, .dayHeader)
    }

    public var rangeText: String? {
        guard let plan else { return nil }
        return PlanCopy.dateRange(format(plan.weekStart, .short), format(plan.endDate, .shortWithMonth))
    }

    public func statusText(_ status: PlanStatusKind) -> String {
        switch status {
        case .draft: return PlanCopy.statusDraft
        case .pendingChanges: return PlanCopy.statusPending
        case .approved(let date):
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = clock.timeZone
            let style = Date.FormatStyle(date: .omitted, time: .omitted, calendar: calendar, timeZone: clock.timeZone)
                .weekday(.abbreviated).day().month(.abbreviated)
            return PlanCopy.statusApproved(date.formatted(style))
        }
    }

    private enum DateStyle { case dayHeader, short, shortWithMonth }

    private func format(_ date: LocalDate, _ style: DateStyle) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = clock.timeZone
        let parts = DateComponents(
            calendar: calendar, timeZone: clock.timeZone, year: date.year, month: date.month, day: date.day, hour: 12)
        guard let instant = calendar.date(from: parts) else { return date.isoString }
        let base = Date.FormatStyle(date: .omitted, time: .omitted, calendar: calendar, timeZone: clock.timeZone)
        switch style {
        case .dayHeader: return instant.formatted(base.weekday(.wide).day())
        case .short: return instant.formatted(base.weekday(.abbreviated).day())
        case .shortWithMonth: return instant.formatted(base.weekday(.abbreviated).day().month(.abbreviated))
        }
    }

    // MARK: Loading

    /// Loads the working plan. Call when the tab appears and after the gate changes.
    public func load() async {
        guard backend != nil else {
            phase = .failed
            return
        }
        do {
            try await reload()
        } catch {
            record(error)
            if plan == nil { phase = .failed }
        }
    }

    private func reload() async throws {
        guard let backend else { return }
        guard let series = try await backend.currentSeriesID() else {
            plan = nil
            approvedPlan = nil
            diff = nil
            phase = .empty
            return
        }
        let working = try await backend.workingPlan(series: series)
        let approved = try await backend.activeApprovedPlan(series: series)
        let pending = try await backend.pendingDiff(series: series)
        plan = working
        approvedPlan = approved
        diff = pending
        phase = working == nil ? .empty : .loaded
    }

    // MARK: Planning actions

    /// "Make a plan" / "Try again" (C-063, C-052).
    public func makePlan() async {
        guard let backend, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        let wasEmpty = plan == nil
        if wasEmpty { phase = .loading }
        do {
            _ = try await backend.generateWeek()
            try await reload()
            errorMessage = nil
        } catch {
            handle(error, planWasMissing: wasEmpty)
        }
    }

    /// After the user confirmed C-074: replaces unlocked meals, keeping locked ones (AC-8.3).
    public func regenerate() async {
        guard let backend, let plan, !isBusy, !isBlocked else { return }
        isBusy = true
        isRegenerating = true
        defer {
            isBusy = false
            isRegenerating = false
        }
        do {
            _ = try await backend.regenerate(plan.id, keepingLocked: true)
            try await reload()
            errorMessage = nil
        } catch {
            handle(error)
        }
    }

    public func toggleLock(_ meal: PlannedMeal) async {
        guard let backend, let plan else { return }
        await perform {
            _ = try await backend.setLocked(!meal.locked, meal: meal.id, in: plan.id)
            try await self.reload()
        }
    }

    public func toggleWhy(_ id: PlannedMealID) {
        if expandedWhy.contains(id) {
            expandedWhy.remove(id)
        } else {
            expandedWhy.insert(id)
        }
    }

    // MARK: Swap (S-12)

    /// Opens the swap sheet. While safety blocks planning it shows C-081 instead (AC-3.3).
    public func openSwap(_ mealID: PlannedMealID) async {
        guard meal(mealID) != nil else { return }
        guard !isBlocked else {
            alert = .blocked(name: blockingName)
            return
        }
        swapMealID = mealID
        swapReason = nil
        swapState = .loading
        sheet = .swap(mealID)
        await loadSwapOptions()
    }

    public func chooseSwapReason(_ reason: RerollReason?) async {
        swapReason = reason == swapReason ? nil : reason
        await loadSwapOptions()
    }

    private func loadSwapOptions() async {
        guard let backend, let plan, let mealID = swapMealID else { return }
        swapState = .loading
        do {
            let found = try await backend.alternatives(for: mealID, in: plan.id, reason: swapReason)
            swapState =
                found.isEmpty
                ? .empty
                : .options(
                    found.map { alternative in
                        let recipe = backend.recipe(alternative.recipeId)
                        let reason = alternative.reasons.lazy.compactMap {
                            PlanCopy.reason($0, ingredientName: { backend.ingredientName($0) })
                        }.first
                        return SwapOption(
                            recipeID: alternative.recipeId, title: recipe?.title ?? PlanCopy.noRecipe,
                            minutes: recipe.map { $0.prepMinutes + $0.cookMinutes }, reason: reason)
                    })
        } catch {
            record(error)
            if let service = error as? ServiceError, case .gateRefused = service {
                sheet = nil
                alert = .blocked(name: blockingName)
            } else {
                swapState = .failed
            }
        }
    }

    public func choose(_ option: SwapOption) async {
        guard let backend, let plan, let mealID = swapMealID else { return }
        let wasApproved = plan.status == .approved
        await perform {
            _ = try await backend.swap(mealID, in: plan.id, to: option.recipeID)
            try await self.reload()
            self.finishSwap(wasApproved: wasApproved)
        }
    }

    public func pickForMe() async {
        guard let backend, let plan, let mealID = swapMealID else { return }
        let wasApproved = plan.status == .approved
        let reason = swapReason
        await perform {
            do {
                _ = try await backend.reroll(mealID, in: plan.id, reason: reason)
            } catch let error as ServiceError {
                if case .noOtherSafeRecipe = error {
                    self.swapState = .empty
                    return
                }
                throw error
            }
            try await self.reload()
            self.finishSwap(wasApproved: wasApproved)
        }
    }

    private func finishSwap(wasApproved: Bool) {
        sheet = nil
        swapMealID = nil
        if wasApproved { toast = PlanCopy.swappedNeedsApproval }
    }

    // MARK: Approval (S-10 bar, S-13)

    /// Whether the approval sheet may open: a draft exists and safety does not block.
    public var canOpenApproval: Bool { isDraft && !isBlocked && !isBusy }

    public func requestApprovalSheet() {
        guard canOpenApproval else { return }
        validationFailed = false
        sheet = .approval
    }

    /// Approves the draft. `confirmation` can only come from the approval controls' tap.
    public func approve(confirmation: UserConfirmation) async {
        guard let backend, let plan, plan.status == .draft, !isBlocked else { return }
        let isRevision = plan.basedOn != nil
        await perform {
            _ = try await backend.approve(plan.id, confirmation: confirmation)
            self.sheet = nil
            try await self.reload()
            self.toast = isRevision ? PlanCopy.changesApproved : PlanCopy.weekApproved
        }
    }

    public func requestDiscard() {
        guard hasPendingChanges else { return }
        isConfirmingDiscard = true
    }

    /// "Discard changes" after the user confirmed C-073: the approved plan stays as it is.
    public func discardChanges() async {
        guard let backend, let plan, plan.status == .draft, plan.basedOn != nil else { return }
        await perform {
            try await backend.discard(plan.id)
            self.sheet = nil
            try await self.reload()
        }
    }

    /// Spoken "approve it" only opens the approval sheet; it never approves (AC-5.6).
    @discardableResult
    public func handleSpokenTranscript(_ transcript: String) -> Bool {
        guard let backend, backend.spokenCommands(in: transcript).contains(.openApprovalSheet), canOpenApproval
        else { return false }
        validationFailed = false
        sheet = .approval
        return true
    }

    /// OK on an alert. After C-071 the affected meals are replaced with a fresh safe plan.
    public func acknowledgeAlert() async {
        let current = alert
        alert = nil
        if current == .validatorFailed {
            await acknowledgeValidatorFailure()
        }
    }

    /// OK on C-071 (alert or inline in the approval sheet): replaces the meals that are no
    /// longer safe by regenerating; locked meals that are still safe stay.
    public func acknowledgeValidatorFailure() async {
        validationFailed = false
        sheet = nil
        await regenerate()
    }

    // MARK: Lunchbox card and school lunches (S-11, S-14)

    /// Called when the meal detail for `meal` appears (AC-7.1).
    public func mealOpened(_ meal: PlannedMeal) async {
        lunchboxCardVisible = false
        guard let backend, meal.slot == .lunch else { return }
        do {
            lunchboxCardVisible = try await backend.lunchboxPromptDue(for: meal.slot)
        } catch {
            record(error)
        }
    }

    public func answerLunchbox(_ answer: LunchboxPromptAnswer) async {
        guard let backend else { return }
        await perform {
            try await backend.answerLunchboxPrompt(answer)
            self.lunchboxCardVisible = false
            if answer == .yes { self.sheet = .schoolLunches }
        }
    }

    /// The children the school lunches sheet offers.
    public var schoolChildren: [Member] {
        (app.household?.activeMembers ?? []).filter(LunchboxService.isSchoolAge)
    }

    public func saveSchoolLunches(children: Set<MemberID>, days: Set<Weekday>) async {
        guard let backend, !children.isEmpty, !days.isEmpty else { return }
        let ordered = schoolChildren.map(\.id).filter { children.contains($0) }
        await perform {
            let refusal = try await backend.setUpSchoolLunches(children: ordered, days: days)
            self.sheet = nil
            try await self.reload()
            self.toast = refusal == nil ? PlanCopy.lunchesSaved : PlanCopy.lunchesSavedLater
        }
    }

    /// "Answer now" on the blocked card: re-evaluates the gate, which shows the safety question
    /// again while anyone is unasked.
    public func answerNow() async {
        await app.refresh()
    }

    // MARK: Plumbing

    private func perform(_ operation: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await operation()
            errorMessage = nil
        } catch {
            handle(error)
        }
    }

    private func handle(_ error: any Error, planWasMissing: Bool = false) {
        record(error)
        if let service = error as? ServiceError {
            switch service {
            case .validationFailed:
                if sheet == .approval {
                    validationFailed = true
                } else {
                    alert = .validatorFailed
                }
                return
            case .gateRefused:
                alert = .blocked(name: blockingName)
                if planWasMissing { phase = .empty }
                return
            default:
                break
            }
        }
        if planWasMissing {
            // Generation failed and there is no plan: C-052 above "Make a plan".
            phase = .empty
            errorMessage = PlanCopy.error
        } else {
            errorMessage = PlanCopy.saveFailed
        }
    }

    private func record(_ error: any Error) {
        let kind = OMPLog.errorKind(error)
        OMPLog.app.error("Plan operation failed: \(kind, privacy: .public)")
    }

    /// The error card's Try again: tries to make the missing plan again, else reloads.
    public func retry() async {
        errorMessage = nil
        if phase == .empty {
            await makePlan()
        } else {
            phase = .loading
            await load()
        }
    }
}
