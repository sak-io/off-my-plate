import SwiftUI

/// The one prominent button style (design-system.md section 1, Colour note): accent background
/// with an `OnAccent` label, so the label keeps its contrast in Dark Mode where the system
/// `borderedProminent` white label fails on the light-green accent.
///
/// Labels wrap (no line limit) and the button is at least 44 pt high (AC-15.1, section 3.4).
public struct OMPPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(isEnabled ? OMPColor.onAccent : Color.secondary)
            .padding(.horizontal, OMPSpacing.medium)
            .padding(.vertical, OMPSpacing.small + 4)
            .frame(maxWidth: .infinity, minHeight: OMPMetrics.minimumHitTarget)
            .background(
                isEnabled ? AnyShapeStyle(OMPColor.accent) : AnyShapeStyle(Color.secondary.opacity(0.2)),
                in: RoundedRectangle(cornerRadius: OMPMetrics.cardCornerRadius, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: OMPMetrics.cardCornerRadius, style: .continuous))
    }
}

extension ButtonStyle where Self == OMPPrimaryButtonStyle {
    /// `Button("Approve week") { ... }.buttonStyle(.ompPrimary)`
    public static var ompPrimary: OMPPrimaryButtonStyle { OMPPrimaryButtonStyle() }
}
