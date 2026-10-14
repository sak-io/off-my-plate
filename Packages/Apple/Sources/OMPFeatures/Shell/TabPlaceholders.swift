import OMPUI
import SwiftUI

/// Placeholder content of a tab until its screens land (T23 Plan, T24 Pantry, T25 List,
/// T27 Household).
struct TabPlaceholder: View {
    let tab: AppTab

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                tab.title,
                systemImage: tab.systemImage,
                description: Text(Self.comingSoon))
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
            ContentUnavailableView(
                AppTab.plan.title,
                systemImage: AppTab.plan.systemImage,
                description: Text(TabPlaceholder.comingSoon))
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

/// The Household tab placeholder with About -> the full disclaimer, so the disclaimer is
/// reachable from anywhere in the app (AC-2.6, AC-14.1, S-37).
struct HouseholdTabPlaceholder: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(TabPlaceholder.comingSoon).foregroundStyle(Color.primary.opacity(0.75))
                }
                Section(Self.aboutTitle) {
                    NavigationLink(Self.disclaimerTitle) {
                        DisclaimerNoteView()
                            .navigationTitle(Self.disclaimerTitle)
                    }
                    .accessibilityIdentifier("household.about.disclaimer")
                }
            }
            .accessibilityIdentifier(AccessibilityID.tabRoot(.household))
            .navigationTitle(AppTab.household.title)
        }
    }

    static var aboutTitle: String {
        String(localized: "shell.household.about", defaultValue: "About", comment: "Household section (C-110).")
    }

    static var disclaimerTitle: String {
        String(
            localized: "shell.household.disclaimer", defaultValue: "Not medical advice",
            comment: "Row that opens the full medical disclaimer (S-37).")
    }
}
