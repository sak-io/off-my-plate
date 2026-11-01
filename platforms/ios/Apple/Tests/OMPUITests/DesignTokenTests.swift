import SwiftUI
import Testing

@testable import OMPUI

/// WCAG 2.x contrast ratio of two 0xRRGGBB colours.
private func contrastRatio(_ first: UInt32, _ second: UInt32) -> Double {
    func luminance(_ hex: UInt32) -> Double {
        let rgb = OMPColor.components(hex)
        func channel(_ value: Double) -> Double {
            value <= 0.039_28 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.red) + 0.7152 * channel(rgb.green) + 0.0722 * channel(rgb.blue)
    }
    let (lighter, darker) = (max(luminance(first), luminance(second)), min(luminance(first), luminance(second)))
    return (lighter + 0.05) / (darker + 0.05)
}

@Suite("Design tokens (design-system.md section 1)")
struct DesignTokenTests {
    private let accent = OMPColor.Variants(
        light: 0x1B6E3A, dark: 0x5CC98A, lightHighContrast: 0x0F4F28, darkHighContrast: 0x86E0AB)
    private let onAccent = OMPColor.Variants(
        light: 0xFFFFFF, dark: 0x0B2A17, lightHighContrast: 0xFFFFFF, darkHighContrast: 0x06180D)

    @Test("Hex components are split into red, green and blue")
    func hexComponents() {
        let rgb = OMPColor.components(0xFF8000)
        #expect(rgb.red == 1)
        #expect(abs(rgb.green - 128.0 / 255) < 0.000_1)
        #expect(rgb.blue == 0)
    }

    @Test("Each appearance picks its own variant")
    func variantSelection() {
        #expect(accent.value(isDark: false, isHighContrast: false) == 0x1B6E3A)
        #expect(accent.value(isDark: true, isHighContrast: false) == 0x5CC98A)
        #expect(accent.value(isDark: false, isHighContrast: true) == 0x0F4F28)
        #expect(accent.value(isDark: true, isHighContrast: true) == 0x86E0AB)
    }

    @Test("OnAccent labels on the accent meet WCAG AA text contrast (4.5:1) in every appearance")
    func onAccentContrast() {
        for isDark in [false, true] {
            for isHighContrast in [false, true] {
                let ratio = contrastRatio(
                    accent.value(isDark: isDark, isHighContrast: isHighContrast),
                    onAccent.value(isDark: isDark, isHighContrast: isHighContrast))
                #expect(ratio >= 4.5, "dark=\(isDark) highContrast=\(isHighContrast): \(ratio)")
            }
        }
    }

    @Test("The accent as text meets 4.5:1 on the system backgrounds")
    func accentOnBackgroundContrast() {
        #expect(contrastRatio(accent.light, 0xFFFFFF) >= 4.5)
        #expect(contrastRatio(accent.lightHighContrast, 0xFFFFFF) >= 4.5)
        // Dark Mode backgrounds: systemBackground #000000, secondarySystemBackground #1C1C1E.
        for background: UInt32 in [0x000000, 0x1C1C1E] {
            #expect(contrastRatio(accent.dark, background) >= 4.5)
            #expect(contrastRatio(accent.darkHighContrast, background) >= 4.5)
        }
    }

    @Test("White on the dark accent fails, which is why OnAccent exists")
    func whiteOnDarkAccentFails() {
        #expect(contrastRatio(accent.dark, 0xFFFFFF) < 4.5)
    }

    @Test("Spacing is 8 / 16 / 24 and hit targets are at least 44 pt")
    func spacingAndHitTarget() {
        #expect([OMPSpacing.small, OMPSpacing.medium, OMPSpacing.large] == [8, 16, 24])
        #expect(OMPMetrics.minimumHitTarget >= 44)
        #expect(OMPMetrics.cardCornerRadius == 12)
    }

    @Test("AdaptiveStack goes vertical from accessibility1 upwards only")
    func adaptiveStackSwitchesAtAccessibilitySizes() {
        #expect(!AdaptiveStack<EmptyView>.isVertical(.xxxLarge))
        #expect(!AdaptiveStack<EmptyView>.isVertical(.large))
        #expect(AdaptiveStack<EmptyView>.isVertical(.accessibility1))
        #expect(AdaptiveStack<EmptyView>.isVertical(.accessibility5))
    }

    @Test("Disclaimers are keyed by copy ids C-090, C-091, C-092 and have English text")
    func disclaimerCopy() {
        #expect(Disclaimer.allCases.map(\.copyID) == ["C-090", "C-091", "C-092"])
        #expect(Disclaimer.safety.text == "OffMyPlate isn't medical advice. Always check ingredients and labels.")
        #expect(Disclaimer.plan.text.contains("Not medical advice"))
        #expect(Disclaimer.fullNote.text.contains("doctor or dietitian"))
        #expect(!Disclaimer.fullNote.text.contains("  "))
    }

    @Test("Every icon token is a distinct SF Symbol name")
    func symbolsAreDistinct() {
        let symbols = [
            OMPSymbol.plan, OMPSymbol.list, OMPSymbol.pantry, OMPSymbol.household, OMPSymbol.draft,
            OMPSymbol.approved, OMPSymbol.locked, OMPSymbol.warning, OMPSymbol.mic, OMPSymbol.listening,
            OMPSymbol.info, OMPSymbol.cooked,
        ]
        #expect(Set(symbols).count == symbols.count)
    }
}
