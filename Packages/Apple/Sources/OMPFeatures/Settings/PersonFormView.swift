import OMPDomain
import OMPUI
import SwiftUI

/// Add or edit a person (S-31; AC-16.1, AC-3.2, AC-3.4). Only existence and the safety answer
/// are required: name and age group are optional.
///
/// Adding a person closes the form and the safety question for them opens straight away (the
/// shell shows the gate cover once the household is reloaded). Changing the age group across
/// child and teen/adult asks the safety question again.
struct PersonFormView: View {
    let viewModel: HouseholdViewModel
    /// The person being edited, or nil when adding.
    let member: Member?
    /// Called after a successful Add (the sheet closes); edits pop the screen themselves.
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var ageBand: AgeBand?
    @State private var isConfirmingRemove = false

    init(viewModel: HouseholdViewModel, member: Member?, onFinished: @escaping () -> Void) {
        self.viewModel = viewModel
        self.member = member
        self.onFinished = onFinished
        _name = State(initialValue: member?.name ?? "")
        _ageBand = State(initialValue: member?.ageBand)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OMPSpacing.medium) {
                Text(SettingsCopy.nameOptional)
                    .font(OMPFont.mealName)
                    .accessibilityAddTraits(.isHeader)
                TextField(placeholder, text: $name)
                    .font(OMPFont.body)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .accessibilityIdentifier(AccessibilityID.personName)

                Picker(SettingsCopy.ageGroupOptional, selection: $ageBand) {
                    ForEach(HouseholdViewModel.ageBands, id: \.self) { band in
                        Text(SettingsCopy.ageGroup(band)).tag(band)
                    }
                }
                .pickerStyle(.menu)
                .font(OMPFont.body)
                .accessibilityIdentifier(AccessibilityID.personAge)

                if member == nil {
                    note(SettingsCopy.askedAfterAdd)
                } else {
                    note(SettingsCopy.ageChangeNote)
                }

                Button(member == nil ? SettingsCopy.add : SettingsCopy.save) {
                    Task { await submit() }
                }
                .buttonStyle(.ompPrimary)
                .accessibilityIdentifier(AccessibilityID.personSave)

                if member == nil {
                    Button(SettingsCopy.cancel) { onFinished() }
                        .buttonStyle(SafetyOutlinedButtonStyle())
                        .accessibilityIdentifier(AccessibilityID.personCancel)
                }

                if let member, viewModel.canRemove(member) {
                    Button {
                        isConfirmingRemove = true
                    } label: {
                        Text(SettingsCopy.removePerson)
                    }
                    .buttonStyle(SafetyOutlinedButtonStyle())
                    .accessibilityIdentifier(AccessibilityID.personRemove)
                }
            }
            .frame(maxWidth: OMPMetrics.coverMaxWidth, alignment: .leading)
            .padding(OMPSpacing.medium)
            .frame(maxWidth: .infinity)
            // The sheet covers the tab's own alert, so a failed Add is reported here.
            .failureAlert(viewModel)
        }
        .background(Color.settingsBackground)
        .accessibilityIdentifier(AccessibilityID.personSheet)
        .navigationTitle(member == nil ? SettingsCopy.addPersonTitle : SettingsCopy.editPersonTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert(
            SettingsCopy.confirmRemove(member?.displayName ?? ""), isPresented: $isConfirmingRemove
        ) {
            Button(SettingsCopy.remove, role: .destructive) {
                Task {
                    if let member, await viewModel.removePerson(member) { dismiss() }
                }
            }
            Button(SettingsCopy.cancel, role: .cancel) {}
        }
    }

    private var placeholder: String {
        member?.label.displayName ?? viewModel.app.household?.nextLabel(for: .adult).displayName ?? ""
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(OMPFont.disclaimer)
            .foregroundStyle(Color.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func submit() async {
        if let member {
            if await viewModel.savePerson(member, name: name, ageBand: ageBand) { dismiss() }
        } else if await viewModel.addPerson(name: name, ageBand: ageBand) {
            onFinished()
        }
    }
}
