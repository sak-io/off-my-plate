import OMPDomain
import OMPUI
import SwiftUI

/// S-12: swap one meal for one of up to three safe alternatives, or "Pick for me" (AC-8.1,
/// AC-8.2). The alternatives come from the planner and are each checked by the validator in
/// `PlanService`; choosing one applies it at once.
struct SwapSheet: View {
    let viewModel: PlanViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(RerollReason.allCases, id: \.self) { reason in
                        Button {
                            Task { await viewModel.chooseSwapReason(reason) }
                        } label: {
                            HStack {
                                Text(PlanCopy.rerollReason(reason)).font(OMPFont.body)
                                Spacer(minLength: 0)
                                if viewModel.swapReason == reason {
                                    Image(systemName: "checkmark").accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(viewModel.swapReason == reason ? .isSelected : [])
                        .accessibilityIdentifier(AccessibilityID.swapReason(reason.rawValue))
                    }
                } header: {
                    Text(PlanCopy.whyChange)
                }
                Section {
                    options
                } header: {
                    Text(PlanCopy.pickOne)
                }
                Section {
                    Button(PlanCopy.pickForMe) { Task { await viewModel.pickForMe() } }
                        .buttonStyle(.bordered)
                        .ompMinimumHitTarget()
                        .disabled(viewModel.isBusy)
                        .accessibilityIdentifier(AccessibilityID.swapPickForMe)
                }
            }
            .accessibilityIdentifier(AccessibilityID.swapSheet)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(PlanCopy.cancel) { viewModel.sheet = nil }
                        .accessibilityIdentifier(AccessibilityID.swapCancel)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var title: String {
        guard let id = viewModel.swapMealID, let meal = viewModel.meal(id) else { return PlanCopy.swap }
        return PlanCopy.swapTitle(day: viewModel.dayTitle(meal.date), meal: PlanCopy.slotName(meal.slot).lowercased())
    }

    @ViewBuilder
    private var options: some View {
        switch viewModel.swapState {
        case .loading:
            ProgressView(PlanCopy.loading)
        case .empty:
            Text(PlanCopy.swapEmpty)
                .font(OMPFont.body)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(AccessibilityID.swapEmpty)
        case .failed:
            Text(PlanCopy.saveFailed)
                .font(OMPFont.body)
                .fixedSize(horizontal: false, vertical: true)
        case .options(let list):
            ForEach(list) { option in
                Button {
                    Task { await viewModel.choose(option) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(optionTitle(option)).font(OMPFont.mealName)
                        if let reason = option.reason {
                            Text(reason)
                                .font(OMPFont.reason)
                                .foregroundStyle(Color.primary.opacity(0.75))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isBusy)
                .accessibilityIdentifier(AccessibilityID.swapOption(option.recipeID.rawValue))
            }
        }
    }

    private func optionTitle(_ option: SwapOption) -> String {
        guard let minutes = option.minutes else { return option.title }
        return "\(option.title) · \(PlanCopy.minutes(minutes))"
    }
}
