import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Colour tokens (docs/design/design-system.md section 1). Everything else uses semantic
/// system colours, which already adapt to Dark Mode and Increase Contrast.
///
/// The accent pair is defined in code rather than in an asset catalog so that OMPUI needs no
/// resources and the share extension gets the same values. Each token has light, dark and
/// Increase Contrast variants.
public enum OMPColor {
    /// Tint, links and the background of prominent buttons. #1B6E3A light, #5CC98A dark.
    public static let accent = dynamic(
        light: 0x1B6E3A, dark: 0x5CC98A, lightHighContrast: 0x0F4F28, darkHighContrast: 0x86E0AB)

    /// Label colour on `accent` backgrounds (primary buttons). White in light mode; a dark
    /// green in Dark Mode, because white on #5CC98A fails contrast.
    public static let onAccent = dynamic(
        light: 0xFFFFFF, dark: 0x0B2A17, lightHighContrast: 0xFFFFFF, darkHighContrast: 0x06180D)

    /// Warning icons (unasked, stale, unrecognised). Always paired with text: the icon is
    /// decorative and the text carries the meaning (AC-15.3).
    public static let warning = Color.orange

    /// Card background: `secondarySystemBackground` on iOS.
    public static var cardBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    /// The four variants of a token as 0xRRGGBB values.
    struct Variants: Sendable, Hashable {
        let light: UInt32
        let dark: UInt32
        let lightHighContrast: UInt32
        let darkHighContrast: UInt32

        /// The value for one appearance.
        func value(isDark: Bool, isHighContrast: Bool) -> UInt32 {
            switch (isDark, isHighContrast) {
            case (false, false): return light
            case (true, false): return dark
            case (false, true): return lightHighContrast
            case (true, true): return darkHighContrast
            }
        }
    }

    /// Red, green and blue in 0...1 from 0xRRGGBB.
    static func components(_ hex: UInt32) -> (red: Double, green: Double, blue: Double) {
        (
            Double((hex >> 16) & 0xFF) / 255,
            Double((hex >> 8) & 0xFF) / 255,
            Double(hex & 0xFF) / 255
        )
    }

    static func dynamic(
        light: UInt32, dark: UInt32, lightHighContrast: UInt32, darkHighContrast: UInt32
    ) -> Color {
        let variants = Variants(
            light: light, dark: dark, lightHighContrast: lightHighContrast,
            darkHighContrast: darkHighContrast)
        #if canImport(UIKit)
        return Color(
            uiColor: UIColor { traits in
                let hex = variants.value(
                    isDark: traits.userInterfaceStyle == .dark,
                    isHighContrast: traits.accessibilityContrast == .high)
                let rgb = OMPColor.components(hex)
                return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
            })
        #else
        return Color(
            nsColor: NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(from: [
                    .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
                ])
                let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
                let isHighContrast =
                    match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
                let rgb = OMPColor.components(variants.value(isDark: isDark, isHighContrast: isHighContrast))
                return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
            })
        #endif
    }
}
