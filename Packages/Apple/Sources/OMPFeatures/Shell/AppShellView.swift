import OMPUI
import SwiftUI

/// The app's root view (task T21): the four tabs, and the safety-gate cover over everything
/// while any member is unasked (screens.md section 1; ADR 0007).
///
/// `TabView` uses `.sidebarAdaptable`: a sidebar on iPad in regular width, a tab bar in compact
/// width. Each tab owns its `NavigationStack`. Tab contents are placeholders until T22-T27.
public struct AppShellView: View {
    private let model: AppModel
    @State private var selection: AppTab = .plan
    @Environment(\.scenePhase) private var scenePhase

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        content
            .tint(OMPColor.accent)
            .task { await model.refresh() }
            .onChange(of: scenePhase) { _, phase in
                // The 180-day re-check depends on today's date, so re-evaluate on every return.
                if phase == .active {
                    Task { await model.refresh() }
                }
            }
            .gateCover(isPresented: model.gateStatus.showsGateCover && !model.onboardingActive) {
                SafetyGateCover(members: model.membersNeedingAnswer, answering: gateAnswering)
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.gateStatus == .loadFailed {
            LoadFailedView()
        } else if model.onboardingActive, let services = model.safetyServices {
            let appModel = model
            OnboardingFlowView(
                services: services, speech: model.speechCapture,
                onFinished: { await appModel.finishOnboarding() })
        } else {
            tabs
        }
    }

    /// What the safety cover needs to take an answer (T22); `nil` when no services are wired.
    private var gateAnswering: GateAnswering? {
        guard let services = model.safetyServices else { return nil }
        let appModel = model
        return GateAnswering(
            services: services, speech: model.speechCapture,
            activeMemberCount: model.household?.activeMembers.count ?? 1,
            onAnswered: { await appModel.refresh() })
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            Tab(AppTab.plan.title, systemImage: AppTab.plan.systemImage, value: AppTab.plan) {
                PlanTabPlaceholder()
            }
            .badge(model.gateStatus.blocksPlanning ? Self.planBadge : nil)

            Tab(AppTab.list.title, systemImage: AppTab.list.systemImage, value: AppTab.list) {
                TabPlaceholder(tab: .list)
            }

            Tab(AppTab.pantry.title, systemImage: AppTab.pantry.systemImage, value: AppTab.pantry) {
                TabPlaceholder(tab: .pantry)
            }

            Tab(AppTab.household.title, systemImage: AppTab.household.systemImage, value: AppTab.household) {
                HouseholdTabPlaceholder()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    /// The Plan tab's "!" badge while safety blocks planning; VoiceOver reads "needs your answer"
    /// (screens.md section 1). No numeric badges anywhere.
    private static var planBadge: Text {
        Text(verbatim: "!")
            .accessibilityLabel(
                String(
                    localized: "shell.tab.plan.badge",
                    defaultValue: "needs your answer",
                    comment: "VoiceOver text of the Plan tab badge while safety blocks planning."))
    }
}

extension View {
    /// Presents `cover` full screen on iOS (a sheet on macOS, where full-screen covers do not
    /// exist). The binding ignores dismissal: only the model can take the cover away.
    @ViewBuilder
    fileprivate func gateCover<Cover: View>(
        isPresented: Bool, @ViewBuilder cover: @escaping () -> Cover
    ) -> some View {
        let binding = Binding<Bool>(get: { isPresented }, set: { _ in })
        #if os(iOS)
        fullScreenCover(isPresented: binding) {
            cover().interactiveDismissDisabled(true)
        }
        #else
        sheet(isPresented: binding) {
            cover().interactiveDismissDisabled(true)
        }
        #endif
    }
}

/// C-096: the store could not be opened.
struct LoadFailedView: View {
    var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: "shell.loadFailed.title", defaultValue: "Can't open your data",
                       comment: "Title when the data store could not be opened at launch."),
                systemImage: OMPSymbol.warning)
        } description: {
            Text(
                String(
                    localized: "C-096",
                    defaultValue: """
                        I couldn't open your data. Restart the app; if it keeps happening, check your \
                        device has free space.
                        """,
                    comment: "Data couldn't load at launch."))
        }
        .accessibilityIdentifier(AccessibilityID.loadFailed)
    }
}
