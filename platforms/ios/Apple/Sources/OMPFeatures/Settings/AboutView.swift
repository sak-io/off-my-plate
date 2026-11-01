import Foundation
import OMPUI
import SwiftUI

/// About, privacy and the medical note (S-37; AC-14.1, AC-2.6). A page, so it cannot be
/// dismissed in place; the full disclaimer is always shown.
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OMPSpacing.medium) {
                section(SettingsCopy.medicalHeader) {
                    Text(Disclaimer.fullNote.text)
                        .font(OMPFont.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("disclaimer.\(Disclaimer.fullNote.copyID)")
                }
                section(SettingsCopy.privacyHeader) {
                    Text(SettingsCopy.privacy)
                        .font(OMPFont.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(SettingsCopy.version(Self.versionText))
                    .font(OMPFont.reason)
                    .accessibilityIdentifier(AccessibilityID.aboutVersion)
            }
            .frame(maxWidth: OMPMetrics.readableMaxWidth, alignment: .leading)
            .padding(OMPSpacing.medium)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier(AccessibilityID.aboutRoot)
        .navigationTitle(SettingsCopy.aboutTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: OMPSpacing.small) {
            Text(title).font(OMPFont.mealName).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    /// "1.0 (3)" from the bundle; plain "1.0" when there is no build number.
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else { return short }
        return "\(short) (\(build))"
    }
}
