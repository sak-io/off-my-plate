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
            content
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AccessibilityID.tabRoot(.plan))
                .navigationTitle(PlanCopy.title)
                .toolbar {
                    if viewModel.plan != nil {
                        ToolbarItem(placement: .primaryAction) {
                            Button(PlanCopy.regenerate) { viewModel.isConfirmingRegenerate = true }
                                .disabled(viewModel.isBlocked || viewModel.isBusy)
                                .accessibilityIdentifier(AccessibilityID.planRegenerate)
                        }
                    }
                }
                .navigationDestination(for: PlannedMealID.self) { id in
                    MealDetailView(viewModel: viewModel, mealID: id)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
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
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
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
                .foregroundStyle(Color.primary.opacity(0.75))
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
            Button(PlanCopy.answerNow) { Task { await viewModel.answerNow() } }
                .buttonStyle(.bordered)
                .ompMinimumHitTarget()
                .accessibilityIdentifier(AccessibilityID.planBlockedAnswer)
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
                .ompMinimumHitTarget()
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
                    ForEach(day.meals) { meal in
                        PlanMealRow(viewModel: viewModel, meal: meal) { path.append(meal.id) }
                    }
                } header: {
                    Text(viewModel.dayTitle(day.date))
                        .font(OMPFont.reason.bold())
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(AccessibilityID.planDay(day.id))
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
                StatusLabel(
                    text, systemImage: Self.symbol(for: status),
                    accessibilityText: PlanCopy.statusAccessibility(text), isHeader: true
                )
                .font(OMPFont.body.bold())
                .accessibilityIdentifier(AccessibilityID.planStatus)
            }
            if let range = viewModel.rangeText {
                Text(range)
                    .font(OMPFont.reason)
                    .foregroundStyle(Color.primary.opacity(0.75))
            }
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
            if viewModel.showsFirstPlanBanner {
                InlineCard(title: PlanCopy.firstPlanBanner) {
                    Button(PlanCopy.dismiss) { viewModel.bannerDismissed = true }
                        .buttonStyle(.bordered)
                        .ompMinimumHitTarget()
                        .accessibilityIdentifier(AccessibilityID.planBannerDismiss)
                }
                .accessibilityIdentifier(AccessibilityID.planBanner)
            }
        }
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
                            .foregroundStyle(Color.primary.opacity(0.75))
                        if meal.isEmpty {
                            Text(PlanCopy.emptySlot).font(OMPFont.mealName)
                        } else {
                            Text(viewModel.title(of: meal)).font(OMPFont.mealName)
                            if let reason = viewModel.reasonLine(of: meal) {
                                Text(reason)
                                    .font(OMPFont.reason)
                                    .foregroundStyle(Color.primary.opacity(0.75))
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.planMeal(id))

            if meal.locked {
                StatusLabel(PlanCopy.locked, systemImage: OMPSymbol.locked)
                    .font(OMPFont.reason)
                    .accessibilityIdentifier(AccessibilityID.planLock(id))
            }
            if meal.isEmpty {
                Button(PlanCopy.emptySlotWhyButton) { viewModel.toggleWhy(meal.id) }
                    .buttonStyle(.bordered)
                    .ompMinimumHitTarget()
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
                .ompMinimumHitTarget()
                .accessibilityLabel(PlanCopy.markMealCooked(viewModel.title(ofRecipe: target.recipeId)))
                .accessibilityIdentifier(AccessibilityID.planMarkCooked(id))
        }
    }
}
