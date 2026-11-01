import OMPDomain
import OMPUI
import SwiftUI

/// The "Approve week" button and its caption (C-062, screens.md S-10).
///
/// This file and `ApprovalSheet.swift` are the only places that create a `UserConfirmation`:
/// the tap on this button is the user's explicit approval (AC-5.2, AC-5.6, ADR 0008;
/// `scripts/lint-safety.sh` enforces the file name). The service still checks the safety gate
/// and re-runs the independent validator before it approves anything.
struct ApprovalWeekBar: View {
    let viewModel: PlanViewModel

    var body: some View {
        Button {
            Task { await viewModel.approve(confirmation: UserConfirmation()) }
        } label: {
            Text(PlanCopy.approveWeek)
        }
        .buttonStyle(.ompPrimary)
        .disabled(viewModel.isBlocked || viewModel.isBusy)
        .accessibilityHint(PlanCopy.approveHint(viewModel.mealCount))
        .accessibilityIdentifier(AccessibilityID.planApprove)
        Text(viewModel.isBlocked ? PlanCopy.blockedHint(viewModel.blockingName) : PlanCopy.approveCaption)
            .font(OMPFont.disclaimer)
            .foregroundStyle(Color.primary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}
