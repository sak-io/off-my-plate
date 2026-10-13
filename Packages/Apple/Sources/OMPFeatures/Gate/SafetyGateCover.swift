import OMPDomain
import OMPUI
import SwiftUI

/// The root safety-gate cover (screens.md S-02 "Gate cover" variant; ADR 0007; AC-3.1, AC-2.6).
///
/// Shown full screen over everything while any member is unasked. It has no close, skip or back
/// button and interactive dismissal is disabled; it goes away only when `AppModel.gateStatus`
/// stops reporting unanswered members. T22 puts the answer controls (`SafetyAnswerView`,
/// "No, nothing", "Added by mistake?") into `answerArea`; T21 provides the frame, the title,
/// the progress text and the disclaimer.
struct SafetyGateCover: View {
    let members: [Member]
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        ScrollView {
            if let member = members.first {
                VStack(alignment: .leading, spacing: OMPSpacing.medium) {
                    if members.count > 1 {
                        Text(Self.progressText(index: 1, total: members.count))
                            .font(OMPFont.reason)
                            .accessibilityIdentifier(AccessibilityID.gateProgress)
                    }
                    Text(Self.title(for: member))
                        .font(OMPFont.sectionTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(AccessibilityID.gateTitle)
                        .accessibilityFocused($titleFocused)
                    Text(Self.reason)
                        .font(OMPFont.body)
                        .fixedSize(horizontal: false, vertical: true)
                    DisclaimerFooter(.safety)
                }
                .frame(maxWidth: OMPMetrics.coverMaxWidth, alignment: .leading)
                .padding(OMPSpacing.large)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityIdentifier(AccessibilityID.gateCover)
        .interactiveDismissDisabled(true)
        .onAppear { titleFocused = true }
    }

    /// C-030: "Does {name} have an allergy or something they must avoid?"
    nonisolated static func title(for member: Member) -> String {
        let name = member.displayName
        return String(
            localized: "C-030",
            defaultValue: "Does \(name) have an allergy or something they must avoid?",
            comment: "Safety gate cover title for one member. %@ is the member's name or label.")
    }

    /// C-030a: "{n} of {total}"
    nonisolated static func progressText(index: Int, total: Int) -> String {
        String(
            localized: "C-030a",
            defaultValue: "\(index) of \(total)",
            comment: "Safety gate cover progress when several members are unasked.")
    }

    /// C-021: why the question is asked.
    nonisolated static var reason: String {
        String(
            localized: "C-021",
            defaultValue: "I'll never put these in a plan, so I need to know before I suggest anything.",
            comment: "One-sentence reason on the safety question (S-02 and gate cover).")
    }
}
