import OMPDomain
import OMPUI
import SwiftUI

/// The Household tab (S-30; task T27): people, safety, what I've learned, About and Delete all
/// data. Replaces the T21 placeholder.
///
/// Compact layout: one `NavigationStack`. Section headers are plain rows (not `Section("...")`)
/// so their colour and size are ours: the default list headers failed the contrast audit.
public struct HouseholdTabView: View {
    private let model: AppModel
    @State private var viewModel: HouseholdViewModel
    @State private var showingAddPerson = false
    @State private var path: [HouseholdRoute] = []

    public init(model: AppModel) {
        self.model = model
        _viewModel = State(initialValue: HouseholdViewModel(app: model))
    }

    public var body: some View {
        NavigationStack(path: $path) {
            List {
                if case .reconfirmationDue = model.gateStatus {
                    Section {
                        ReconfirmCardView(
                            summary: viewModel.safetySummary,
                            onYes: { Task { _ = await viewModel.reconfirm() } },
                            onChange: { path.append(.rules) }
                        )
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }
                peopleSection
                safetySection
                planSection
                aboutSection
            }
            .settingsListStyle()
            .accessibilityIdentifier(AccessibilityID.tabRoot(.household))
            .navigationTitle(AppTab.household.title)
            .navigationDestination(for: HouseholdRoute.self) { route in
                switch route {
                case .person(let id):
                    if let member = viewModel.members.first(where: { $0.id == id }) {
                        PersonFormView(viewModel: viewModel, member: member, onFinished: {})
                    }
                case .rules: SafetyRulesView(viewModel: viewModel)
                case .learned: LearnedView(app: model)
                case .about: AboutView()
                }
            }
            .alert(SettingsCopy.deleteConfirmTitle, isPresented: $viewModel.isConfirmingDeleteAll) {
                Button(SettingsCopy.deleteEverything, role: .destructive) { Task { await viewModel.deleteAll() } }
                Button(SettingsCopy.cancel, role: .cancel) {}
            }
        }
        .sheet(
            isPresented: $showingAddPerson,
            onDismiss: {
                // The new person is unasked: reload only now, so the safety cover is not asked
                // to appear while this sheet is still going away.
                Task { await model.refresh() }
            }
        ) {
            NavigationStack {
                PersonFormView(viewModel: viewModel, member: nil, onFinished: { showingAddPerson = false })
            }
        }
        .failureAlert(viewModel)
    }

    // MARK: Sections

    private var peopleSection: some View {
        Section {
            SettingsSectionHeader(title: SettingsCopy.people)
            ForEach(Array(viewModel.members.enumerated()), id: \.element.id) { index, member in
                Button {
                    path.append(.person(member.id))
                } label: {
                    SettingsRowLabel {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.displayName).font(OMPFont.mealName)
                        HStack(alignment: .firstTextBaseline, spacing: OMPSpacing.small) {
                            if viewModel.status(of: member) == .notAnswered {
                                Image(systemName: OMPSymbol.warning)
                                    .foregroundStyle(OMPColor.warning)
                                    .accessibilityHidden(true)
                            }
                            Text(viewModel.statusText(of: member))
                                .font(OMPFont.reason)
                                .foregroundStyle(Color.primary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AccessibilityID.householdPerson + String(index))
            }
            Button {
                showingAddPerson = true
            } label: {
                SettingsIconRow(systemImage: "plus", title: SettingsCopy.addPerson)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isAvailable)
            .accessibilityIdentifier(AccessibilityID.householdAddPerson)
        }
    }

    private var safetySection: some View {
        Section {
            SettingsSectionHeader(title: SettingsCopy.safety)
            Button {
                path.append(.rules)
            } label: {
                SettingsRowLabel { Text(SettingsCopy.allergiesRow).font(OMPFont.body) }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.householdAllergies)
        }
    }

    private var planSection: some View {
        Section {
            SettingsSectionHeader(title: SettingsCopy.yourPlan)
            Button {
                path.append(.learned)
            } label: {
                SettingsRowLabel { Text(SettingsCopy.learnedRow).font(OMPFont.body) }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.householdLearned)
        }
    }

    private var aboutSection: some View {
        Section {
            SettingsSectionHeader(title: SettingsCopy.about)
            Button {
                path.append(.about)
            } label: {
                SettingsRowLabel { Text(SettingsCopy.aboutRow).font(OMPFont.body) }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.householdAbout)
            Button {
                viewModel.isConfirmingDeleteAll = true
            } label: {
                SettingsIconRow(systemImage: "trash", title: SettingsCopy.deleteAllRow)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isAvailable)
            .accessibilityIdentifier(AccessibilityID.householdDeleteAll)
        }
    }
}

/// A section title as a list row: a plain header trait, in the primary colour.
struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(OMPFont.mealName)
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// C-040: "Still correct?" (G3, the 180-day re-check). One tap re-confirms; "Make changes" opens
/// the allergies screen. Nothing changes until the user taps one of the two.
struct ReconfirmCardView: View {
    let summary: String?
    let onYes: () -> Void
    let onChange: () -> Void

    var body: some View {
        InlineCard(
            title: SettingsCopy.stillCorrectTitle,
            message: summary.map(SettingsCopy.stillCorrectBody) ?? SettingsCopy.stillCorrectNone,
            systemImage: OMPSymbol.warning
        ) {
            VStack(alignment: .leading, spacing: OMPSpacing.small) {
                Button(SettingsCopy.yesStillCorrect, action: onYes)
                    .buttonStyle(.bordered)
                    .tint(Color.primary)
                    .ompMinimumHitTarget()
                    .accessibilityIdentifier(AccessibilityID.reconfirmYes)
                Button(SettingsCopy.makeChanges, action: onChange)
                    .buttonStyle(.bordered)
                    .tint(Color.primary)
                    .ompMinimumHitTarget()
                    .accessibilityIdentifier(AccessibilityID.reconfirmChange)
            }
        }
        .accessibilityIdentifier(AccessibilityID.reconfirmCard)
    }
}

extension View {
    /// The C-095 / delete-failed alert of `viewModel`. Attached on every screen that can start a
    /// change, because an alert on a covered view (under a sheet or a pushed screen) never shows.
    func failureAlert(_ viewModel: HouseholdViewModel) -> some View {
        alert(
            viewModel.failureMessage ?? "",
            isPresented: Binding(
                get: { viewModel.failureMessage != nil }, set: { if !$0 { viewModel.dismissFailure() } })
        ) {
            Button(SettingsCopy.ok, role: .cancel) {}
        }
    }
}

/// Where the Household tab can go.
enum HouseholdRoute: Hashable {
    case person(MemberID)
    case rules
    case learned
    case about
}

/// A tappable list row: content, then a chevron in the primary colour. The system disclosure
/// indicator is drawn in a secondary colour that failed the contrast audit.
struct SettingsRowLabel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: OMPSpacing.small) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .foregroundStyle(Color.primary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, OMPSpacing.small)
        .frame(minHeight: OMPMetrics.minimumHitTarget)
        .contentShape(Rectangle())
    }
}

/// An icon and a wrapping title in the primary colour (Add person, Delete all data).
struct SettingsIconRow: View {
    let systemImage: String
    let title: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: OMPSpacing.small) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.primary)
                .accessibilityHidden(true)
            Text(title)
                .font(OMPFont.body)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, OMPSpacing.small)
        .frame(minHeight: OMPMetrics.minimumHitTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension Color {
    /// An opaque background the contrast audit can measure text against.
    static var settingsBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
}

extension View {
    /// A plain list on an explicit opaque background, rows on the same colour: with the default
    /// translucent grouped styling the audit had no known colour to measure text against.
    func settingsListStyle() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.settingsBackground)
            .listRowBackground(Color.settingsBackground)
    }
}
