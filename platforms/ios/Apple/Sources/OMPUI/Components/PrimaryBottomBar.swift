import SwiftUI

extension View {
    /// Pins `content` (for example "Approve week" or "Review changes") to the bottom with
    /// `safeAreaInset`, so the scrolling content above is never hidden behind it
    /// (design-system.md section 3.1). Buttons stack vertically at accessibility text sizes.
    public func ompPrimaryBottomBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let bar = content()
        return safeAreaInset(edge: .bottom, spacing: 0) {
            AdaptiveStack(spacing: OMPSpacing.small) {
                bar
            }
            .padding(OMPSpacing.medium)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }
}
