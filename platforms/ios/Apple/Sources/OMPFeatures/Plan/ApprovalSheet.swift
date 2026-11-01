import OMPDomain
import OMPUI
import SwiftUI

/// S-13: the approval sheet. It lists what changes ("Was" / "Now"), or for a first plan says
/// what is being approved, and approves only when the user taps "Approve" (AC-5.2, AC-5.4,
/// AC-5.6). Voice and anything else can only open this sheet.
///
/// `UserConfirmation()` is created here, in the button handler, and nowhere else besides
/// `ApprovalWeekBar.swift` (ADR 0008, `scripts/lint-safety.sh`).
struct ApprovalSheet: View {
    let viewModel: PlanViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: OMPSpacing.small) {
                        Text(title)
                            .font(OMPFont.sectionTitle.bold())
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(subtitle)
                            .font(OMPFont.body)
                            .foregroundStyle(Color.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .listRowBackground(Color.clear)
                }
                ForEach(Array(changes.enumerated()), id: \.offset) { index, change in
                    Section {
                        let diffLines = lines(for: change)
                        ForEach(Array(diffLines.enumerated()), id: \.offset) { _, line in
                            Text(line).font(OMPFont.body).fixedSize(horizontal: false, vertical: true)
                        }
                    } header: {
                        Text(PlanCopy.diffHeader(day: viewModel.dayTitle(change.date), meal: PlanCopy.slotName(change.slot)))
                            .font(OMPFont.reason.bold())
                            .foregroundStyle(Color.primary)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .accessibilityIdentifier(AccessibilityID.approvalChange(index))
                }
                Section {
                    safetyLine
                }
            }
            .accessibilityIdentifier(AccessibilityID.approvalSheet)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(PlanCopy.notYet) { viewModel.sheet = nil }
                        .accessibilityIdentifier(AccessibilityID.approvalNotYet)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { buttons }
        }
        .presentationDetents([.medium, .large])
        .confirmationDialog(
            PlanCopy.discardConfirmTitle, isPresented: discardBinding, titleVisibility: .visible
        ) {
            Button(PlanCopy.discard, role: .destructive) { Task { await viewModel.discardChanges() } }
            Button(PlanCopy.keepEditing, role: .cancel) {}
        }
    }

    // MARK: Content

    private var changes: [PlanDiff.Change] {
        viewModel.diff?.listedChanges ?? []
    }

    private var title: String {
        if viewModel.hasPendingChanges {
            return changes.isEmpty ? PlanCopy.approveChangesQuestion : PlanCopy.approveChangesTitle(changes.count)
        }
        return PlanCopy.approveWeekTitle
    }

    private var subtitle: String {
        viewModel.hasPendingChanges ? PlanCopy.everythingElse : PlanCopy.approveWeekDetail
    }

    /// "Was" / "Now" words, never colour alone; one line per kind of change.
    private func lines(for change: PlanDiff.Change) -> [String] {
        var lines: [String] = []
        for kind in change.kinds {
            switch kind {
            case .swapped:
                if let was = change.was { lines.append(PlanCopy.was(viewModel.title(ofRecipe: was.recipeId))) }
                if let now = change.now { lines.append(PlanCopy.now(viewModel.title(ofRecipe: now.recipeId))) }
            case .emptied:
                if let was = change.was { lines.append(PlanCopy.was(viewModel.title(ofRecipe: was.recipeId))) }
                lines.append(PlanCopy.nowEmpty)
            case .added:
                lines.append(PlanCopy.addedSlot)
                if let now = change.now { lines.append(PlanCopy.now(viewModel.title(ofRecipe: now.recipeId))) }
            case .removed:
                if let was = change.was { lines.append(PlanCopy.was(viewModel.title(ofRecipe: was.recipeId))) }
                lines.append(PlanCopy.removedSlot)
            case .servingsChanged:
                lines.append(PlanCopy.portionsChanged)
            case .lockChanged:
                break  // not listed: a lock does not change the food
            }
        }
        return lines
    }

    @ViewBuilder
    private var safetyLine: some View {
        if viewModel.validationFailed {
            VStack(alignment: .leading, spacing: OMPSpacing.small) {
                StatusLabel(PlanCopy.validatorFailed, systemImage: OMPSymbol.warning)
                    .accessibilityIdentifier(AccessibilityID.approvalFailed)
                Button(PlanCopy.ok) { Task { await viewModel.acknowledgeValidatorFailure() } }
                    .buttonStyle(.bordered)
                    .tint(Color.primary)                    .ompMinimumHitTarget()
                    .accessibilityIdentifier(AccessibilityID.approvalFailedOK)
            }
        } else {
            StatusLabel(PlanCopy.safetyCheckPassed, systemImage: OMPSymbol.cooked)
                .accessibilityIdentifier(AccessibilityID.approvalSafety)
        }
    }

    private var buttons: some View {
        VStack(spacing: OMPSpacing.small) {
            Button {
                Task { await viewModel.approve(confirmation: UserConfirmation()) }
            } label: {
                if viewModel.isBusy {
                    ProgressView()
                } else {
                    Text(viewModel.hasPendingChanges ? PlanCopy.approveChanges : PlanCopy.approveWeek)
                }
            }
            .buttonStyle(.ompPrimary)
            .disabled(viewModel.validationFailed || viewModel.isBusy || viewModel.isBlocked)
            .accessibilityIdentifier(AccessibilityID.approvalApprove)

            if viewModel.hasPendingChanges {
                Button {
                    viewModel.requestDiscard()
                } label: {
                    Label(PlanCopy.discardChanges, systemImage: "trash")
                        .foregroundStyle(Color.primary)
                }
                .buttonStyle(.bordered)
                .tint(Color.primary)                .ompMinimumHitTarget()
                    .disabled(viewModel.isBusy)
                    .accessibilityIdentifier(AccessibilityID.approvalDiscard)
            }
        }
        .padding(OMPSpacing.medium)
        .frame(maxWidth: .infinity)
        .planBarBackground()
    }

    private var discardBinding: Binding<Bool> {
        Binding(get: { viewModel.isConfirmingDiscard }, set: { viewModel.isConfirmingDiscard = $0 })
    }
}
