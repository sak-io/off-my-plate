import SwiftUI

/// A rounded card with a title, a message and up to three buttons (design-system.md section 2):
/// lunchbox prompt, reflect-back, blocked by safety, 180-day re-check, new member and so on.
///
/// VoiceOver reads the title and message as one group, then the buttons. Buttons are laid out
/// with `AdaptiveStack`, so they stack vertically at accessibility text sizes.
public struct InlineCard<Actions: View>: View {
    private let title: String
    private let message: String?
    private let systemImage: String?
    private let actions: Actions

    /// - Parameters:
    ///   - title: the card title (already localized).
    ///   - message: optional body text.
    ///   - systemImage: optional SF Symbol shown before the title; decorative.
    ///   - actions: at most three buttons.
    public init(
        title: String, message: String? = nil, systemImage: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actions = actions()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: OMPSpacing.small) {
            VStack(alignment: .leading, spacing: OMPSpacing.small) {
                HStack(alignment: .firstTextBaseline, spacing: OMPSpacing.small) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .foregroundStyle(systemImage == OMPSymbol.warning ? OMPColor.warning : .secondary)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .font(OMPFont.mealName)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let message {
                    Text(message)
                        .font(OMPFont.reason)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            AdaptiveStack(spacing: OMPSpacing.small) {
                actions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OMPSpacing.medium)
        .ompCardBackground()
        .accessibilityElement(children: .contain)
    }
}

extension InlineCard where Actions == EmptyView {
    /// A card without buttons.
    public init(title: String, message: String? = nil, systemImage: String? = nil) {
        self.init(title: title, message: message, systemImage: systemImage) { EmptyView() }
    }
}
