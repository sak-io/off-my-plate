import Observation
import OMPDomain
import OMPServices
import OMPUI
import SwiftUI

/// The "add something to avoid" sheet's state (S-33 add flow). Nothing is saved until the user
/// confirms on the second step ("Yes, save this", AC-2.3, AC-3.5); text the app cannot map to a
/// catalog restriction never counts as checked (AC-2.4).
@MainActor
@Observable
final class AddRuleModel {
    enum Phase: Equatable { case entry, summary }

    private(set) var phase: Phase = .entry
    var scope: RuleScope = .household
    private(set) var chosen: [RestrictionID] = []
    private(set) var unrecognised: [String] = []
    var draftText = ""
    private let read: (String) -> SafetyTextReading

    init(read: @escaping (String) -> SafetyTextReading) {
        self.read = read
    }

    func isChosen(_ id: RestrictionID) -> Bool { chosen.contains(id) }

    func toggle(_ id: RestrictionID) {
        if let index = chosen.firstIndex(of: id) {
            chosen.remove(at: index)
        } else {
            chosen.append(id)
        }
    }

    /// Adds what the typed text names; words that match nothing are listed until removed.
    func submitText() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        draftText = ""
        guard !text.isEmpty else { return }
        let reading = read(text)
        for id in reading.restrictions where !chosen.contains(id) { chosen.append(id) }
        for word in reading.unrecognised where !unrecognised.contains(word) { unrecognised.append(word) }
    }

    func removeUnrecognised(_ word: String) {
        unrecognised.removeAll { $0 == word }
    }

    /// Continue is possible once something is chosen and nothing is left unresolved (C-025).
    var canContinue: Bool { !chosen.isEmpty && unrecognised.isEmpty }

    func continueToSummary() {
        guard canContinue else { return }
        phase = .summary
    }

    func backToEntry() { phase = .entry }

    /// What "Yes, save this" sends to the safety service.
    var requests: [RuleRequest] {
        chosen.map { RuleRequest(restriction: $0, scope: scope) }
    }
}

/// Allergies & must-avoid foods (S-33; AC-3.5): hard rules by person, add and remove with
/// confirmation. Every change goes through `SafetyService`, which re-validates open plans.
struct SafetyRulesView: View {
    let viewModel: HouseholdViewModel
    /// Set when shown in a sheet (Plan tab): a Done button closes it.
    var onDone: (() -> Void)?

    @State private var showingAdd = false
    @State private var rowToRemove: RuleRow?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OMPSpacing.medium) {
                let groups = viewModel.ruleGroups
                if groups.isEmpty {
                    Text(SettingsCopy.nobodyAvoids)
                        .font(OMPFont.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(AccessibilityID.rulesEmpty)
                }
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: OMPSpacing.small) {
                        Text(group.title)
                            .font(OMPFont.mealName)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.rows) { row in
                            ruleRow(row, index: rowIndex(of: row))
                        }
                    }
                }
                Button {
                    showingAdd = true
                } label: {
                    Label(SettingsCopy.add, systemImage: "plus")
                }
                .buttonStyle(SafetyOutlinedButtonStyle())
                .accessibilityIdentifier(AccessibilityID.rulesAdd)
                DisclaimerFooter(.safety)
            }
            .frame(maxWidth: OMPMetrics.readableMaxWidth, alignment: .leading)
            .padding(OMPSpacing.medium)
            .frame(maxWidth: .infinity)
            .failureAlert(viewModel)
        }
        .accessibilityIdentifier(AccessibilityID.rulesRoot)
        .navigationTitle(SettingsCopy.allergiesRow)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let onDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button(SettingsCopy.done, action: onDone)
                        .accessibilityIdentifier(AccessibilityID.rulesDone)
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddRuleSheet(viewModel: viewModel)
        }
        .alert(
            rowToRemove.map { SettingsCopy.confirmRemoveRule(item: $0.item, name: $0.who ?? SettingsCopy.everyone) }
                ?? "",
            isPresented: Binding(
                get: { rowToRemove != nil }, set: { if !$0 { rowToRemove = nil } }),
            presenting: rowToRemove
        ) { row in
            Button(SettingsCopy.remove, role: .destructive) {
                Task { _ = await viewModel.removeRule(row) }
            }
            Button(SettingsCopy.cancel, role: .cancel) {}
        }
    }

    private func rowIndex(of row: RuleRow) -> Int {
        viewModel.ruleRows.firstIndex { $0.id == row.id } ?? 0
    }

    private func ruleRow(_ row: RuleRow, index: Int) -> some View {
        AdaptiveStack(spacing: OMPSpacing.small) {
            Text(row.item)
                .font(OMPFont.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(SettingsCopy.remove) { rowToRemove = row }
                .buttonStyle(SafetyOutlinedButtonStyle())
                .accessibilityLabel("\(SettingsCopy.remove) \(row.item)")
                .accessibilityIdentifier(AccessibilityID.rulesRemove(index))
        }
        .padding(OMPSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ompCardBackground()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.rulesRow(index))
    }
}

/// The add flow: pick or type what to avoid and for whom, check it, then "Yes, save this".
struct AddRuleSheet: View {
    let viewModel: HouseholdViewModel
    @State private var model: AddRuleModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var textFocused: Bool

    init(viewModel: HouseholdViewModel) {
        self.viewModel = viewModel
        _model = State(initialValue: AddRuleModel(read: { viewModel.readSafetyText($0) }))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OMPSpacing.medium) {
                    switch model.phase {
                    case .entry: entry
                    case .summary: summary
                    }
                    // In the content, not the toolbar: a navigation-bar text button cannot scale.
                    Button(SettingsCopy.cancel) { dismiss() }
                        .buttonStyle(SafetyOutlinedButtonStyle())
                        .accessibilityIdentifier(AccessibilityID.addRuleCancel)
                }
                .frame(maxWidth: OMPMetrics.coverMaxWidth, alignment: .leading)
                .padding(OMPSpacing.medium)
                .frame(maxWidth: .infinity)
            }
            .background(Color.settingsBackground)
            .navigationTitle(SettingsCopy.addRuleTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .failureAlert(viewModel)
        .accessibilityIdentifier(AccessibilityID.addRuleSheet)
    }

    @ViewBuilder
    private var entry: some View {
        if viewModel.members.count > 1 {
            Picker(SettingsCopy.forWhom, selection: $model.scope) {
                ForEach(viewModel.scopeOptions) { option in
                    Text(option.title).tag(option.scope)
                }
            }
            .pickerStyle(.menu)
            .font(OMPFont.body)
            .accessibilityIdentifier(AccessibilityID.addRuleWho)
        }

        FlowLayout {
            ForEach(viewModel.restrictionChoices) { restriction in
                ChipToggle(
                    title: SafetyCopy.label(for: restriction),
                    isSelected: model.isChosen(restriction.id),
                    identifier: AccessibilityID.addRuleChip(restriction.id.rawValue)
                ) {
                    model.toggle(restriction.id)
                }
            }
        }

        Text(SettingsCopy.orTellMe)
            .font(OMPFont.reason)
            .accessibilityAddTraits(.isHeader)
        AdaptiveStack(spacing: OMPSpacing.small) {
            TextField(SettingsCopy.typeToAdd, text: $model.draftText, axis: .vertical)
                .lineLimit(1...4)
                .font(OMPFont.body)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .focused($textFocused)
                .onSubmit {
                    model.submitText()
                    textFocused = false
                }
                .accessibilityIdentifier(AccessibilityID.addRuleText)
            Button(SettingsCopy.addText) {
                model.submitText()
                textFocused = false
            }
            .buttonStyle(SafetyOutlinedButtonStyle())
            .accessibilityIdentifier(AccessibilityID.addRuleTextAdd)
        }

        ForEach(model.unrecognised, id: \.self) { word in
            VStack(alignment: .leading, spacing: OMPSpacing.small) {
                Label {
                    Text(SettingsCopy.cannotCheck(word))
                        .font(OMPFont.reason)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: OMPSymbol.warning).foregroundStyle(OMPColor.warning).accessibilityHidden(true)
                }
                Button(SettingsCopy.remove) { model.removeUnrecognised(word) }
                    .buttonStyle(SafetyOutlinedButtonStyle())
                    .accessibilityLabel("\(SettingsCopy.remove) \(word)")
            }
            .padding(OMPSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ompCardBackground()
        }

        DisclaimerFooter(.safety)

        Button(SettingsCopy.review) { model.continueToSummary() }
            .buttonStyle(.ompPrimary)
            .disabled(!model.canContinue)
            .accessibilityIdentifier(AccessibilityID.addRuleContinue)
    }

    @ViewBuilder
    private var summary: some View {
        Text(SettingsCopy.checkTitle)
            .font(OMPFont.sectionTitle.bold())
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(AccessibilityID.addRuleSummary)
        let who = viewModel.scopeTitle(model.scope)
        ForEach(model.chosen, id: \.self) { id in
            Text(SettingsCopy.avoidsFor(item: viewModel.label(for: id), who: who))
                .font(OMPFont.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        DisclaimerFooter(.safety)
        Button(SettingsCopy.yesSave) {
            Task {
                if await viewModel.addRules(model.requests) { dismiss() }
            }
        }
        .buttonStyle(.ompPrimary)
        .accessibilityIdentifier(AccessibilityID.addRuleSave)
        Button(SettingsCopy.change) { model.backToEntry() }
            .buttonStyle(SafetyOutlinedButtonStyle())
            .accessibilityIdentifier(AccessibilityID.addRuleChange)
    }
}
