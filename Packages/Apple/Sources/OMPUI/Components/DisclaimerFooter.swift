import SwiftUI

/// The medical disclaimer (US-14; AC-2.6, AC-14.1). Persistent and never dismissible: there is
/// no close button and no way to hide it.
///
/// Strings come from the app's String Catalog, keyed by copy id (docs/design/copy.md).
public enum Disclaimer: Sendable, CaseIterable {
    /// C-090: the safety screen and the must-avoid list (S-02, S-33).
    case safety
    /// C-091: the plan and the meal detail footer (S-10, S-11).
    case plan
    /// C-092: the full note (Settings -> About, S-37).
    case fullNote

    /// The copy id this text is keyed by in `Localizable.xcstrings`.
    public var copyID: String {
        switch self {
        case .safety: return "C-090"
        case .plan: return "C-091"
        case .fullNote: return "C-092"
        }
    }

    /// The localized text.
    public var text: String {
        switch self {
        case .safety:
            return String(
                localized: "C-090",
                defaultValue: "OffMyPlate isn't medical advice. Always check ingredients and labels.",
                comment: "Disclaimer footer on the safety question and the must-avoid list (S-02, S-33).")
        case .plan:
            return String(
                localized: "C-091",
                defaultValue: "Not medical advice. Check ingredients and labels, especially for allergies.",
                comment: "Disclaimer footer on the plan and meal detail (S-10, S-11).")
        case .fullNote:
            return String(
                localized: "C-092",
                defaultValue: """
                    OffMyPlate suggests meals based on what you tell it. It isn't medical advice and \
                    can't guarantee a dish is free of allergens: packaged ingredients can contain hidden \
                    allergens or traces. Always check ingredients and labels. For allergies or medical \
                    diets, follow advice from your doctor or dietitian.
                    """,
                comment: "Full medical disclaimer note (S-37, Settings -> About).")
        }
    }
}

/// A `.footnote` label with an info icon showing one disclaimer. Wraps at every text size.
public struct DisclaimerFooter: View {
    private let disclaimer: Disclaimer

    public init(_ disclaimer: Disclaimer) {
        self.disclaimer = disclaimer
    }

    public var body: some View {
        Label {
            Text(disclaimer.text)
                .font(OMPFont.disclaimer)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: OMPSymbol.info)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("disclaimer.\(disclaimer.copyID)")
    }
}

/// The full disclaimer as a page (S-37). Reachable from Household -> About (AC-2.6).
public struct DisclaimerNoteView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            Text(Disclaimer.fullNote.text)
                .font(OMPFont.body)
                .frame(maxWidth: OMPMetrics.readableMaxWidth, alignment: .leading)
                .padding(OMPSpacing.medium)
                .accessibilityIdentifier("disclaimer.\(Disclaimer.fullNote.copyID)")
        }
    }
}
