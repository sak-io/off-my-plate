import OMPDomain
import OMPUI
import SwiftUI

/// What I've learned (S-35; AC-12.5): every active and proposed soft fact in plain words with
/// where it came from, grouped by origin. Facts shape suggestions only; allergies and
/// must-avoid foods are set in S-33 and never here (AC-12.4).
struct LearnedView: View {
    @State private var viewModel: LearningViewModel
    @State private var household: HouseholdViewModel
    @State private var openFact: FactID?
    @State private var showingSafety = false

    init(app: AppModel) {
        _viewModel = State(initialValue: LearningViewModel(app: app))
        _household = State(initialValue: HouseholdViewModel(app: app))
    }

    var body: some View {
        content
            .accessibilityIdentifier(AccessibilityID.learnedRoot)
            .navigationTitle(SettingsCopy.learnedRow)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(item: $openFact) { id in
                if let fact = viewModel.fact(id) { FactSheetView(viewModel: viewModel, fact: fact) }
            }
            .navigationDestination(isPresented: $showingSafety) {
                SafetyRulesView(viewModel: household)
            }
            #if os(iOS)
            // A pushed detail screen: the tab bar would float over the last rows.
            .toolbarVisibility(.hidden, for: .tabBar)
            #endif
            .task { await viewModel.load() }
            .alert(SettingsCopy.saveFailed, isPresented: $viewModel.saveFailed) {
                Button(SettingsCopy.ok, role: .cancel) {}
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            ScrollView {
                VStack(spacing: OMPSpacing.medium) {
                    Text(SettingsCopy.loadFailed)
                        .font(OMPFont.body)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier(AccessibilityID.learnedLoadFailed)
                    Button(SettingsCopy.tryAgain) { Task { await viewModel.load() } }
                        .buttonStyle(.ompPrimary)
                }
                .padding(OMPSpacing.large)
                .frame(maxWidth: .infinity)
            }
        case .loaded:
            list.alert(
                SettingsCopy.forgetConfirm,
                isPresented: Binding(
                    get: { viewModel.pendingForget != nil },
                    set: { if !$0 { viewModel.pendingForget = nil } }),
                presenting: viewModel.pendingForget
            ) { fact in
                Button(SettingsCopy.forget, role: .destructive) { Task { await viewModel.forget(fact) } }
                Button(SettingsCopy.cancel, role: .cancel) {}
            }
        }
    }

    private var list: some View {
        let flat = viewModel.sections.flatMap { $0.facts }
        return List {
            Section {
                Text(SettingsCopy.learnedIntro)
                    .font(OMPFont.body)
                    .foregroundStyle(Color.primary)
                    .accessibilityIdentifier(AccessibilityID.learnedIntro)
                if viewModel.isEmpty {
                    Text(SettingsCopy.learnedEmpty)
                        .font(OMPFont.body)
                        .foregroundStyle(Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(AccessibilityID.learnedEmpty)
                }
            }
            ForEach(viewModel.sections) { group in
                Section {
                    SettingsSectionHeader(title: group.section.title)
                    ForEach(group.facts) { fact in
                        let index = flat.firstIndex { $0.id == fact.id } ?? 0
                        row(fact, index: index)
                    }
                }
            }
            Section {
                Button {
                    showingSafety = true
                } label: {
                    SettingsRowLabel {
                        Label {
                            Text(SettingsCopy.safetyPointer)
                                .font(OMPFont.disclaimer)
                                .foregroundStyle(Color.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: OMPSymbol.info).foregroundStyle(Color.primary).accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(AccessibilityID.learnedSafetyLink)
            }
        }
        .settingsListStyle()
    }

    @ViewBuilder
    private func row(_ fact: Fact, index: Int) -> some View {
        VStack(alignment: .leading, spacing: OMPSpacing.small) {
        Button {
            openFact = fact.id
        } label: {
            SettingsRowLabel {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.sentence(fact)).font(OMPFont.mealName)
                    if let word = viewModel.confidenceWord(fact) {
                        Text(word).font(OMPFont.reason).foregroundStyle(Color.primary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.learnedRow(index))
        if viewModel.canQuickConfirm(fact) {
            Button(SettingsCopy.thatsRight) { Task { await viewModel.thatsRight(fact) } }
                .buttonStyle(SafetyOutlinedButtonStyle())
                .accessibilityIdentifier(AccessibilityID.learnedConfirm(index))
        }
        }
        .swipeActions(edge: .trailing) {
            Button(SettingsCopy.forget, role: .destructive) { viewModel.requestForget(fact) }
        }
    }
}

/// One fact (S-36): the statement, where it came from, who it applies to, and for recipes how
/// strongly. Saving makes it a fact the user stated. There is no "never" or "allergic" choice.
struct FactSheetView: View {
    enum Strength: Hashable { case prefer, avoid }

    let viewModel: LearningViewModel
    let fact: Fact
    @Environment(\.dismiss) private var dismiss
    @State private var subject: FactSubject
    @State private var strength: Strength
    @State private var isConfirmingForget = false

    init(viewModel: LearningViewModel, fact: Fact) {
        self.viewModel = viewModel
        self.fact = fact
        _subject = State(initialValue: fact.subject)
        switch fact.statement {
        case .favouriteRecipe: _strength = State(initialValue: .prefer)
        case .dislikesRecipe, .dislikesIngredient, .cuisineAffinity, .prefersQuickWeekday, .staple:
            _strength = State(initialValue: .avoid)
        }
    }

    private var pair: (prefer: FactStatement, avoid: FactStatement)? {
        LearningViewModel.strengthOptions(for: fact.statement)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OMPSpacing.medium) {
                Text(viewModel.sentence(fact))
                    .font(OMPFont.sectionTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 2) {
                    Text(SettingsCopy.whereFrom).font(OMPFont.mealName)
                    Text(viewModel.text.origin(of: fact)).font(OMPFont.body)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AccessibilityID.factOrigin)

                Picker(SettingsCopy.appliesTo, selection: $subject) {
                    ForEach(viewModel.subjects) { option in
                        Text(option.title).tag(option.subject)
                    }
                }
                .pickerStyle(.menu)
                .font(OMPFont.body)
                .accessibilityIdentifier(AccessibilityID.factWho)

                if pair != nil {
                    Picker(SettingsCopy.strength, selection: $strength) {
                        Text(SettingsCopy.prefer).tag(Strength.prefer)
                        Text(SettingsCopy.avoidWhenPossible).tag(Strength.avoid)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier(AccessibilityID.factStrength)
                }

                Button(SettingsCopy.save) {
                    Task {
                        await viewModel.save(fact, subject: subject, statement: chosenStatement)
                        dismiss()
                    }
                }
                .buttonStyle(.ompPrimary)
                .accessibilityIdentifier(AccessibilityID.factSave)

                Button {
                    isConfirmingForget = true
                } label: {
                    Text(SettingsCopy.forgetThis)
                }
                .buttonStyle(SafetyOutlinedButtonStyle())
                .accessibilityIdentifier(AccessibilityID.factForget)

                Label {
                    Text(SettingsCopy.safetyPointer)
                        .font(OMPFont.disclaimer)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: OMPSymbol.info).foregroundStyle(Color.primary).accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: OMPMetrics.coverMaxWidth, alignment: .leading)
            .padding(OMPSpacing.medium)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier(AccessibilityID.factSheet)
        .navigationTitle(SettingsCopy.factTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert(SettingsCopy.forgetConfirm, isPresented: $isConfirmingForget) {
            Button(SettingsCopy.forget, role: .destructive) {
                Task {
                    await viewModel.forget(fact)
                    dismiss()
                }
            }
            Button(SettingsCopy.cancel, role: .cancel) {}
        }
    }

    /// The statement to save: unchanged, or the other side of a prefer/avoid pair.
    private var chosenStatement: FactStatement {
        guard let pair else { return fact.statement }
        return strength == .prefer ? pair.prefer : pair.avoid
    }
}
