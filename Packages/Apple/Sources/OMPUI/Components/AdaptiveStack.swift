import SwiftUI

/// A horizontal stack that becomes vertical at accessibility text sizes (design-system.md
/// section 3.1): "label + value" rows, steppers and bottom-bar buttons stack vertically from
/// `.accessibility1` up, so nothing is truncated (AC-15.1).
public struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = OMPSpacing.small, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        let layout =
            Self.isVertical(dynamicTypeSize)
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: .center, spacing: spacing))
        layout { content }
    }

    /// Whether the stack is vertical at `size`: from `.accessibility1` upwards.
    nonisolated public static func isVertical(_ size: DynamicTypeSize) -> Bool {
        size.isAccessibilitySize
    }
}
