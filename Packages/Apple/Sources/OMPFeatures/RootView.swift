import OMPUI
import SwiftUI

/// The app's root view. Walking skeleton (task T02): a placeholder home screen that
/// navigates to a second screen. Task T21 replaces it with the tab shell and the gate cover.
public struct RootView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            HomePlaceholderView()
        }
    }
}

/// Accessibility identifiers the UI tests query (`App/OffMyPlateUITests`). The UI tests run
/// out of process and cannot import this module, so they repeat these strings.
enum AccessibilityID {
    static let homeTitle = "home.title"
    static let homeOpenNext = "home.openNext"
    static let secondTitle = "second.title"
}

struct HomePlaceholderView: View {
    var body: some View {
        VStack(spacing: 24) {
            PlaceholderMessage(
                title: "OffMyPlate",
                message: "Your weekly meal plan will appear here.",
                titleIdentifier: AccessibilityID.homeTitle
            )
            NavigationLink("Open the next screen") {
                SecondPlaceholderView()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(AccessibilityID.homeOpenNext)
        }
        .navigationTitle("Home")
    }
}

struct SecondPlaceholderView: View {
    var body: some View {
        PlaceholderMessage(
            title: "Next screen",
            message: "More of OffMyPlate is on its way.",
            titleIdentifier: AccessibilityID.secondTitle
        )
        .navigationTitle("Next")
    }
}
