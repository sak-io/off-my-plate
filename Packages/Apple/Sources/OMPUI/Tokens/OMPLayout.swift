import SwiftUI

/// Spacing for custom stacks (design-system.md section 1). Lists and forms keep their defaults.
public enum OMPSpacing {
    /// 8 pt: between related items, and the minimum gap between small targets (WCAG 2.5.8).
    public static let small: CGFloat = 8
    /// 16 pt: default padding and spacing between groups.
    public static let medium: CGFloat = 16
    /// 24 pt: between sections of a custom screen.
    public static let large: CGFloat = 24
}

/// Shape and size tokens.
public enum OMPMetrics {
    /// Corner radius of cards (`InlineCard`, gate cover card).
    public static let cardCornerRadius: CGFloat = 12
    /// Minimum hit target for every control, 44 x 44 pt (design-system.md section 3.4).
    public static let minimumHitTarget: CGFloat = 44
    /// Maximum readable width of the onboarding and safety cover card on iPad.
    public static let coverMaxWidth: CGFloat = 600
    /// Maximum readable width of single-column lists in regular width.
    public static let readableMaxWidth: CGFloat = 700
}

/// Typography tokens: system text styles only, so Dynamic Type scales everything (AC-15.1).
/// No fixed point sizes anywhere.
public enum OMPFont {
    public static let screenTitle: Font = .largeTitle
    public static let sectionTitle: Font = .title2
    public static let mealName: Font = .headline
    public static let body: Font = .body
    public static let reason: Font = .subheadline
    public static let disclaimer: Font = .footnote
    public static let caption: Font = .caption
}

/// SF Symbol names (design-system.md "Icons"). Always paired with text or an accessibility
/// label: never icon or colour alone.
public enum OMPSymbol {
    public static let plan = "fork.knife"
    public static let list = "checklist"
    public static let pantry = "refrigerator"
    public static let household = "house"
    public static let draft = "pencil.circle"
    public static let approved = "checkmark.seal"
    public static let locked = "lock.fill"
    public static let warning = "exclamationmark.triangle"
    public static let mic = "mic"
    public static let listening = "waveform"
    public static let info = "info.circle"
    public static let cooked = "checkmark.circle.fill"
}

extension View {
    /// Grows the view's tappable area to at least 44 x 44 pt (design-system.md section 3.4).
    public func ompMinimumHitTarget() -> some View {
        frame(minWidth: OMPMetrics.minimumHitTarget, minHeight: OMPMetrics.minimumHitTarget)
            .contentShape(Rectangle())
    }

    /// Card background: rounded rectangle on the secondary background.
    public func ompCardBackground() -> some View {
        background(
            OMPColor.cardBackground,
            in: RoundedRectangle(cornerRadius: OMPMetrics.cardCornerRadius, style: .continuous))
    }
}
