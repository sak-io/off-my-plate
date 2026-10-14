import OMPDomain
import OMPUI
import SwiftUI

/// The Plan tab (screens S-10, S-10b; task T23): the week, its status, the approve and review
/// bars, and the sheets S-12 to S-14. Replaces the T21 placeholder.
///
/// Compact layout only for now: a `NavigationStack` pushing the meal detail. The iPad split view
/// of screens.md section 1 is a follow-up (tracked in the T23 hand-off).
public struct PlanTabView: View {
    private let model: AppModel
    @State private var viewModel: PlanViewModel
    @State private var path: [PlannedMealID] = []

    public init(model: AppModel) {
        self.model = model
        _viewModel = State(
            initialValue: PlanViewModel(backend: model.planBackend, app: model, clock: model.clock))
    }

    public var body: some View {
        NavigationStack(path: $path) {
            // The bar sits BELOW the list in a stack, not over it as a safe-area inset: rows that
            // scroll under an inset stay in the accessibility tree and the audit measures their
            // contrast against the bar (Dinner, Kerala rasam ... contrast failures, batch 3).
            VStack(spacing: 0) {
                content
                bottomBar
            }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AccessibilityID.tabRoot(.plan))
                .navigationTitle(PlanCopy.title)
                .navigationDestination(for: PlannedMealID.self) { id in
                    MealDetailView(viewModel: viewModel, mealID: id)
                }
        }
        .task(id: model.gateStatus) { await viewModel.load() }
        .sheet(item: sheetBinding) { sheet in
            switch sheet {
            case .approval: ApprovalSheet(viewModel: viewModel)
            case .swap: SwapSheet(viewModel: viewModel)
            case .schoolLunches: SchoolLunchesSheet(viewModel: viewModel)
            }
        }
        .confirmationDialog(
            PlanCopy.regenerateConfirm, isPresented: regenerateBinding, titleVisibility: .visible
        ) {
            Button(PlanCopy.replace, role: .destructive) { Task { await viewModel.regenerate() } }
            Button(PlanCopy.cancel, role: .cancel) {}
        }
        .alert(
            alertText ?? "", isPresented: alertBinding, presenting: viewModel.alert
        ) { _ in
            Button(PlanCopy.ok) { Task { await viewModel.acknowledgeAlert() } }
        }
        .ompToast($viewModel.toast)
    }

    // MARK: Bindings

    private var sheetBinding: Binding<PlanSheet?> {
        Binding(get: { viewModel.sheet }, set: { viewModel.sheet = $0 })
    }

    private var regenerateBinding: Binding<Bool> {
        Binding(get: { viewModel.isConfirmingRegenerate }, set: { viewModel.isConfirmingRegenerate = $0 })
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.alert != nil },
            set: { if !$0 { viewModel.alert = nil } })
    }

    private var alertText: String? {
        switch viewModel.alert {
        case .validatorFailed: return PlanCopy.validatorFailed
        case .blocked(let name): return PlanCopy.blockedHint(name)
        case nil: return nil
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            PlanLoadingView()
        case .failed:
            PlanMessageView(
                symbol: OMPSymbol.warning, title: PlanCopy.error, buttonTitle: PlanCopy.tryAgain,
                buttonID: AccessibilityID.planErrorRetry, enabled: !viewModel.isBusy,
                id: AccessibilityID.planError
            ) { Task { await viewModel.retry() } }
        case .empty:
            PlanEmptyView(viewModel: viewModel)
        case .loaded:
            PlanWeekList(viewModel: viewModel, path: $path)
        }
    }

    /// The approve or review bar (screens.md S-10): only for a draft.
    @ViewBuilder
    private var bottomBar: some View {
        if viewModel.phase == .loaded, viewModel.isDraft {
            VStack(spacing: OMPSpacing.small) {
                if viewModel.isFirstDraft {
                    ApprovalWeekBar(viewModel: viewModel)
                } else {
                    ReviewChangesBar(viewModel: viewModel)
                }
            }
            .padding(OMPSpacing.medium)
            // Extra room above the floating tab bar (iOS 26 glass): the audit measured the caption
            // and button against its edge (batch 3: 'Text clipped' / contrast on the bar content).
            .padding(.bottom, OMPSpacing.large)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .planBarBackground()
        }
    }
}

extension View {
    /// An opaque bottom-bar background: a translucent `.bar` lets rows scroll underneath it and
    /// fails the contrast audit.
    func planBarBackground() -> some View {
        background {
            VStack(spacing: 0) {
                Divider()
                Color.planBarFill
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

extension Color {
    fileprivate static var planBarFill: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
}

/// "Review n changes" (C-070): opens the approval sheet; it approves nothing by itself.
struct ReviewChangesBar: View {
    let viewModel: PlanViewModel

    var body: some View {
        Button {
            viewModel.requestApprovalSheet()
        } label: {
            Text(viewModel.changeCount > 0 ? PlanCopy.reviewChanges(viewModel.changeCount) : PlanCopy.approveChanges)
        }
        .buttonStyle(.ompPrimary)
        .disabled(viewModel.isBlocked || viewModel.isBusy)
        .accessibilityIdentifier(AccessibilityID.planReviewChanges)
        if viewModel.isBlocked {
            Text(PlanCopy.blockedHint(viewModel.blockingName))
                .font(OMPFont.disclaimer)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Phases

struct PlanLoadingView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: OMPSpacing.medium) {
                ProgressView()
                Text(PlanCopy.loading)
                    .font(OMPFont.body)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier(AccessibilityID.planLoading)
                DisclaimerFooter(.plan)
            }
            .frame(maxWidth: .infinity)
            .padding(OMPSpacing.large)
        }
    }
}

/// A message with one button, for the load-failed state.
struct PlanMessageView: View {
    let symbol: String
    let title: String
    let buttonTitle: String
    let buttonID: String
    let enabled: Bool
    let id: String
    let action: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: OMPSpacing.medium) {
                Image(systemName: symbol).font(.largeTitle).accessibilityHidden(true)
                Text(title)
                    .font(OMPFont.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(id)
                Button(buttonTitle, action: action)
                    .buttonStyle(.ompPrimary)
                    .disabled(!enabled)
                    .accessibilityIdentifier(buttonID)
                DisclaimerFooter(.plan)
            }
            .frame(maxWidth: OMPMetrics.coverMaxWidth)
            .padding(OMPSpacing.large)
            .frame(maxWidth: .infinity)
        }
    }
}

/// C-063: no plan yet. A plain layout, not `ContentUnavailableView` (it failed the Dynamic
/// Type audit).
struct PlanEmptyView: View {
    let viewModel: PlanViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: OMPSpacing.medium) {
                if viewModel.isBlocked {
                    PlanBlockedCard(viewModel: viewModel)
                }
                if let message = viewModel.errorMessage {
                    PlanErrorCard(message: message, viewModel: viewModel)
                }
                Image(systemName: OMPSymbol.plan).font(.largeTitle).accessibilityHidden(true)
                Text(PlanCopy.noPlan)
                    .font(OMPFont.sectionTitle.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(AccessibilityID.planEmpty)
                Button(PlanCopy.makePlan) { Task { await viewModel.makePlan() } }
                    .buttonStyle(.ompPrimary)
                    .disabled(viewModel.isBlocked || viewModel.isBusy)
                    .accessibilityIdentifier(AccessibilityID.planMakePlan)
                if viewModel.isBusy {
                    ProgressView(PlanCopy.loading)
                }
                DisclaimerFooter(.plan)
            }
            .frame(maxWidth: OMPMetrics.coverMaxWidth)
            .padding(OMPSpacing.large)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: Cards

/// S-10b: safety blocks planning. Not dismissible.
struct PlanBlockedCard: View {
    let viewModel: PlanViewModel

    var body: some View {
        InlineCard(
            title: PlanCopy.blockedCard(viewModel.blockingName), systemImage: OMPSymbol.warning
        ) {
            if viewModel.canAnswerNow {
                Button(PlanCopy.answerNow) { Task { await viewModel.answerNow() } }
                    .buttonStyle(.bordered)
                    .tint(Color.primary)                    .ompMinimumHitTarget()
                    .accessibilityIdentifier(AccessibilityID.planBlockedAnswer)
            }
        }
        .accessibilityIdentifier(AccessibilityID.planBlocked)
    }
}

/// C-052 / C-095 with Try again; the previous plan stays visible below.
struct PlanErrorCard: View {
    let message: String
    let viewModel: PlanViewModel

    var body: some View {
        InlineCard(title: message, systemImage: OMPSymbol.warning) {
            Button(PlanCopy.tryAgain) { Task { await viewModel.retry() } }
                .buttonStyle(.bordered)
                .tint(Color.primary)                .ompMinimumHitTarget()
                .accessibilityIdentifier(AccessibilityID.planErrorRetry)
        }
        .accessibilityIdentifier(AccessibilityID.planError)
    }
}

// MARK: The week

struct PlanWeekList: View {
    let viewModel: PlanViewModel
    @Binding var path: [PlannedMealID]

    var body: some View {
        List {
            Section {
                header
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            ForEach(viewModel.days) { day in
                Section {
                    Text(viewModel.dayTitle(day.date))
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(AccessibilityID.planDay(day.id))
                    ForEach(day.meals) { meal in
                        PlanMealRow(viewModel: viewModel, meal: meal) { path.append(meal.id) }
                    }
                }
            }
            Section {
                DisclaimerFooter(.plan)
                    .listRowBackground(Color.clear)
            }
        }
        .accessibilityIdentifier(AccessibilityID.planList)
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: OMPSpacing.small) {
            if let status = viewModel.status {
                let text = viewModel.statusText(status)
                HStack(alignment: .firstTextBaseline, spacing: OMPSpacing.small) {
                    Image(systemName: Self.symbol(for: status))
                        .foregroundStyle(OMPColor.accent)
                        .accessibilityHidden(true)
                    Text(text)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(PlanCopy.statusAccessibility(text))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(AccessibilityID.planStatus)
            }
            if let range = viewModel.rangeText {
                Text(range)
                    .font(OMPFont.reason)
                    .foregroundStyle(Color.primary)
            }
            Button(PlanCopy.regenerate) { viewModel.isConfirmingRegenerate = true }
                .buttonStyle(.bordered)
                .tint(Color.primary)
                .ompMinimumHitTarget()
                .disabled(viewModel.isBlocked || viewModel.isBusy)
                .accessibilityIdentifier(AccessibilityID.planRegenerate)
            if viewModel.isRegenerating {
                ProgressView(PlanCopy.loading)
                    .accessibilityIdentifier(AccessibilityID.planLoading)
            }
            if viewModel.isBlocked {
                PlanBlockedCard(viewModel: viewModel)
            }
            if let message = viewModel.errorMessage {
                PlanErrorCard(message: message, viewModel: viewModel)
            }
            if viewModel.hasBlockedMeals {
                InlineCard(title: PlanCopy.safetyChanged, systemImage: OMPSymbol.warning) {
                    Button(PlanCopy.updatePlan) { Task { await viewModel.updatePlan() } }
                        .buttonStyle(.bordered)
                        .tint(Color.primary)                        .ompMinimumHitTarget()
                        .disabled(viewModel.isBlocked || viewModel.isBusy)
                        .accessibilityIdentifier(AccessibilityID.planUpdate)
                }
                .accessibilityIdentifier(AccessibilityID.planSafetyChanged)
            }
            if viewModel.showsFirstPlanBanner {
                InlineCard(title: PlanCopy.firstPlanBanner) {
                    Button(PlanCopy.dismiss) { viewModel.bannerDismissed = true }
                        .buttonStyle(.bordered)
                        .tint(Color.primary)                        .ompMinimumHitTarget()
                        .accessibilityIdentifier(AccessibilityID.planBannerDismiss)
                }
                .accessibilityIdentifier(AccessibilityID.planBanner)
            }
        }
        .padding(.horizontal, OMPSpacing.medium)
        .padding(.vertical, OMPSpacing.small)
    }

    private static func symbol(for status: PlanStatusKind) -> String {
        switch status {
        case .draft, .pendingChanges: return OMPSymbol.draft
        case .approved: return OMPSymbol.approved
        }
    }
}

/// One meal in the week list (S-10): slot, name, reason, lock, the changed lines of a pending
/// revision, the empty-slot reason, and Mark cooked (approved plans only).
struct PlanMealRow: View {
    let viewModel: PlanViewModel
    let meal: PlannedMeal
    let open: () -> Void

    var body: some View {
        let id = meal.id.rawValue
        let placeholder = viewModel.isRegenerating && !meal.locked
        VStack(alignment: .leading, spacing: OMPSpacing.small) {
            Button(action: open) {
                HStack(alignment: .firstTextBaseline, spacing: OMPSpacing.small) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(PlanCopy.slotName(meal.slot))
                            .font(OMPFont.reason)
                            .foregroundStyle(Color.primary)
                        if meal.isEmpty {
                            Text(PlanCopy.emptySlot).font(OMPFont.mealName)
                        } else {
                            Text(viewModel.title(of: meal)).font(OMPFont.mealName)
                            if let reason = viewModel.reasonLine(of: meal) {
                                Text(reason)
                                    .font(OMPFont.reason)
                                    .foregroundStyle(Color.primary)
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.primary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.planMeal(id))

            if viewModel.isMealBlocked(meal) {
                StatusLabel(PlanCopy.mealNeedsReplacing, systemImage: OMPSymbol.warning)
                    .font(OMPFont.reason)
                    .accessibilityIdentifier(AccessibilityID.planBlockedMeal(id))
            }
            if meal.locked {
                StatusLabel(PlanCopy.locked, systemImage: OMPSymbol.locked)
                    .font(OMPFont.reason)
                    .accessibilityIdentifier(AccessibilityID.planLock(id))
            }
            if meal.isEmpty {
                Button(PlanCopy.emptySlotWhyButton) { viewModel.toggleWhy(meal.id) }
                    .buttonStyle(.bordered)
                    .tint(Color.primary)                    .ompMinimumHitTarget()
                    .accessibilityIdentifier(AccessibilityID.planWhy(id))
                if viewModel.expandedWhy.contains(meal.id) {
                    Text(PlanCopy.emptySlotWhy)
                        .font(OMPFont.reason)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(AccessibilityID.planWhyText(id))
                }
            }
            if let change = viewModel.change(for: meal) {
                changedLines(change, id: id)
            }
            cookedControls(id: id)
        }
        .padding(.vertical, OMPSpacing.small)
        .redacted(reason: placeholder ? .placeholder : [])
        .allowsHitTesting(!placeholder)
        .swipeActions(edge: .leading) {
            Button(PlanCopy.swap) { Task { await viewModel.openSwap(meal.id) } }
                .tint(OMPColor.accent)
                .disabled(viewModel.isBlocked || viewModel.isBusy)
        }
        .swipeActions(edge: .trailing) {
            Button(meal.locked ? PlanCopy.unlock : PlanCopy.lock) { Task { await viewModel.toggleLock(meal) } }
                .disabled(viewModel.isBusy)
        }
        .contextMenu {
            Button(PlanCopy.open, action: open)
            Button(PlanCopy.swap) { Task { await viewModel.openSwap(meal.id) } }
                .disabled(viewModel.isBlocked || viewModel.isBusy)
            Button(meal.locked ? PlanCopy.unlock : PlanCopy.lock) { Task { await viewModel.toggleLock(meal) } }
                .disabled(viewModel.isBusy)
        }
    }

    @ViewBuilder
    private func changedLines(_ change: PlanDiff.Change, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            StatusLabel(PlanCopy.changed, systemImage: OMPSymbol.draft)
                .font(OMPFont.reason.bold())
            if let was = change.was {
                Text(PlanCopy.approvedMeal(viewModel.title(ofRecipe: was.recipeId)))
                    .font(OMPFont.reason)
            }
            if let now = change.now {
                Text(PlanCopy.proposedMeal(viewModel.title(ofRecipe: now.recipeId)))
                    .font(OMPFont.reason)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.planChanged(id))
    }

    @ViewBuilder
    private func cookedControls(id: String) -> some View {
        if viewModel.isCooked(meal) {
            StatusLabel(PlanCopy.cooked, systemImage: OMPSymbol.cooked)
                .font(OMPFont.reason)
                .accessibilityIdentifier(AccessibilityID.planCooked(id))
        } else if let target = viewModel.cookableMeal(for: meal) {
            Button(PlanCopy.markCooked) { viewModel.requestMarkCooked(meal) }
                .buttonStyle(.bordered)
                .tint(Color.primary)                .ompMinimumHitTarget()
                .accessibilityLabel(PlanCopy.markMealCooked(viewModel.title(ofRecipe: target.recipeId)))
                .accessibilityIdentifier(AccessibilityID.planMarkCooked(id))
        }
    }
}
