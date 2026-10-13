import SwiftUI

/// A centred title and message, used by the walking-skeleton screens in the app and the
/// share extension (kept for the share extension; the design system is in Tokens/ and Components/).
public struct PlaceholderMessage: View {
    private let title: LocalizedStringKey
    private let message: LocalizedStringKey
    private let titleIdentifier: String

    /// - Parameters:
    ///   - title: shown as a header.
    ///   - message: secondary text under the title.
    ///   - titleIdentifier: accessibility identifier of the title, for UI tests.
    public init(title: LocalizedStringKey, message: LocalizedStringKey, titleIdentifier: String) {
        self.title = title
        self.message = message
        self.titleIdentifier = titleIdentifier
    }

    public var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.title)
                .bold()
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(titleIdentifier)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
