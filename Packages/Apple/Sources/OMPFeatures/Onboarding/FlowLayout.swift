import OMPUI
import SwiftUI

/// Lays chips out left to right and wraps them onto new lines (S-02 and S-03 chips). Every
/// chip is offered the full row width, so a long label wraps inside its chip instead of
/// being cut off at large text sizes.
struct FlowLayout: Layout {
    var spacing: CGFloat = OMPFlow.spacing

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        return arrange(maxWidth: maxWidth, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let result = arrange(maxWidth: bounds.width, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if maxWidth.isFinite { size.width = min(size.width, maxWidth) }
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (frames, CGSize(width: widest, height: y + rowHeight))
    }
}

enum OMPFlow {
    /// Gap between chips: at least 8 pt so neighbouring targets do not touch (WCAG 2.5.8).
    static let spacing: CGFloat = 8
}

/// A toggle chip (S-02 restrictions, S-03 cuisines): at least 44 pt high, a check mark when
/// selected (never colour alone), the label wraps.
struct ChipToggle: View {
    let title: String
    let isSelected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: OMPSpacing.small / 2) {
                if isSelected {
                    Image(systemName: "checkmark").accessibilityHidden(true)
                }
                Text(title)
                    .font(OMPFont.body)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, OMPSpacing.medium - 4)
            .padding(.vertical, OMPSpacing.small)
            .frame(minHeight: OMPMetrics.minimumHitTarget)
            .foregroundStyle(isSelected ? OMPColor.onAccent : Color.primary)
            .background(
                isSelected ? AnyShapeStyle(OMPColor.accent) : AnyShapeStyle(OMPColor.cardBackground),
                in: RoundedRectangle(cornerRadius: OMPMetrics.cardCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OMPMetrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isSelected ? 0 : 0.4), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: OMPMetrics.cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}
