import OMPDomain
import OMPUI
import SwiftUI

/// What sits above the week on the Plan tab (task T27): the "Still correct?" card when the 180-day
/// re-check is due (C-040), else the safety summary with Change (C-061), and the reflect-back card
/// (C-100, never while a safety card shows). Change and "Make changes" open the allergies
/// screen in a sheet; "Yes, still correct" re-confirms through `SafetyService`.
struct PlanSafetyStrip: View {
    let model: AppModel
    let reflect: ReflectBackModel
    /// Called after the safety answers changed, so the plan reloads.
    let onSafetyChanged: () async -> Void

    @State private var household: HouseholdViewModel
    @State private var showingRules = false

    init(model: AppModel, reflect: ReflectBackModel, onSafetyChanged: @escaping () async -> Void) {
        self.model = model
        self.reflect = reflect
        self.onSafetyChanged = onSafetyChanged
        _household = State(initialValue: HouseholdViewModel(app: model))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OMPSpacing.small) {
            if household.isAvailable, model.household != nil {
                safetyCard
            }
            if !model.gateStatus.blocksPlanning {
                ReflectBackCardView(model: reflect)
            }
        }
        .padding(.horizontal, OMPSpacing.medium)
        .padding(.vertical, OMPSpacing.small)
        .sheet(
            isPresented: $showingRules,
            onDismiss: { Task { await onSafetyChanged() } }
        ) {
            NavigationStack {
                SafetyRulesView(viewModel: household, onDone: { showingRules = false })
            }
        }
    }

    @ViewBuilder
    private var safetyCard: some View {
        switch model.gateStatus {
        case .reconfirmationDue:
            ReconfirmCardView(
                summary: household.safetySummary,
                onYes: {
                    Task {
                        if await household.reconfirm() { await onSafetyChanged() }
                    }
                },
                onChange: { showingRules = true })
        case .clear:
            AdaptiveStack(spacing: OMPSpacing.small) {
                Text(SettingsCopy.safetySummaryLine(household.safetySummary ?? SettingsCopy.summaryNobody))
                    .font(OMPFont.reason)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(AccessibilityID.planSafetySummary)
                Button(SettingsCopy.change) { showingRules = true }
                    .buttonStyle(.bordered)
                    .tint(Color.primary)
                    .ompMinimumHitTarget()
                    .accessibilityIdentifier(AccessibilityID.planSafetyChange)
            }
        case .loading, .noHousehold, .unanswered, .loadFailed:
            EmptyView()
        }
    }
}
