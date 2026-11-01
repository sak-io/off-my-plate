import SwiftUI

/// A state shown as a word plus an SF Symbol, never colour alone (AC-15.3). The base of
/// `PlanStatusLabel` (S-10 header, iPad sidebar) and the pantry and list state labels.
public struct StatusLabel: View {
    private let text: String
    private let systemImage: String
    private let accessibilityText: String?
    private let isHeader: Bool

    /// - Parameters:
    ///   - text: the visible word(s), already localized.
    ///   - systemImage: SF Symbol; decorative because `text` carries the meaning.
    ///   - accessibilityText: a fuller spoken label, e.g. "Plan status: draft, not in use yet".
    ///   - isHeader: adds the header trait (plan status).
    public init(_ text: String, systemImage: String, accessibilityText: String? = nil, isHeader: Bool = false) {
        self.text = text
        self.systemImage = systemImage
        self.accessibilityText = accessibilityText
        self.isHeader = isHeader
    }

    public var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(systemImage == OMPSymbol.warning ? OMPColor.warning : OMPColor.accent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText ?? text))
        .accessibilityAddTraits(isHeader ? .isHeader : [])
    }
}
