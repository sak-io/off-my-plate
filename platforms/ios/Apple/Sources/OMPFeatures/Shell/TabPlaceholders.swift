import OMPUI
import SwiftUI

/// Placeholder content of a tab until its screens land (T23 Plan, T24 Pantry, T25 List,
/// T27 Household).
struct TabPlaceholder: View {
    let tab: AppTab

    var body: some View {
        NavigationStack {
            PlaceholderBody(title: tab.title, systemImage: tab.systemImage, message: Self.comingSoon)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AccessibilityID.tabRoot(tab))
                .navigationTitle(tab.title)
        }
    }

    static var comingSoon: String {
        String(
            localized: "shell.placeholder.message", defaultValue: "This part of OffMyPlate is on its way.",
            comment: "Placeholder text on a tab whose screens are not built yet.")
    }
}

/// The Plan tab placeholder, with the plan disclaimer footer (AC-14.1, C-091).
struct PlanTabPlaceholder: View {
    var body: some View {
        NavigationStack {
            PlaceholderBody(title: AppTab.plan.title, systemImage: AppTab.plan.systemImage, message: TabPlaceholder.comingSoon)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AccessibilityID.tabRoot(.plan))
                .safeAreaInset(edge: .bottom) {
                    DisclaimerFooter(.plan)
                        .padding(OMPSpacing.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle(AppTab.plan.title)
        }
    }
}

/// The body of a tab placeholder: symbol, title and message in plain text styles, in a scroll
/// view so it stays usable at every Dynamic Type size.
private struct PlaceholderBody: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ScrollView {
            VStack(spacing: OMPSpacing.small) {
                Image(systemName: systemImage)
                    .font(.largeTitle)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.body)
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(OMPSpacing.large)
        }
    }
}
