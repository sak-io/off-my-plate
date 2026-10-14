import OMPDomain
import OMPUI
import SwiftUI

/// S-21: add or edit one pantry item (AC-9.1, AC-9.2). A plain scroll layout with visible
/// labels, not a `Form`, so no default section headers (LESSONS).
struct PantryFormSheet: View {
    let viewModel: PantryViewModel
    @State private var form: PantryFormModel
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(viewModel: PantryViewModel, backend: any PantryBackend, item: PantryItem?, prefill: PantryFormPrefill?) {
        self.viewModel = viewModel
        _form = State(
            initialValue: PantryFormModel(
                backend: backend, clock: viewModel.domainClock, item: item,
                displayName: item.map { viewModel.displayName(of: $0) } ?? "", prefill: prefill))
    }

    var body: some View {
        NavigationStack {
            // The Save bar sits BELOW the scrolling form in a stack (not a safe-area inset), so
            // the keyboard lifts it and it is never hidden while typing.
            VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: OMPSpacing.medium) {
                    if let transcript = form.transcript {
                        Text(PantryCopy.youSaid(transcript))
                            .font(OMPFont.reason)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(AccessibilityID.pantryFormTranscript)
                    }
                    nameField
                    suggestions
                    amountRow
                    locationPicker
                    useBy
                    if let message = form.errorMessage {
                        InlineCard(title: message, systemImage: OMPSymbol.warning)
                            .accessibilityIdentifier(AccessibilityID.pantryFormError)
                    }
                }
                .frame(maxWidth: OMPMetrics.readableMaxWidth, alignment: .leading)
                .padding(OMPSpacing.medium)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier(AccessibilityID.pantryForm)
            bottomBar
            }
            .navigationTitle(form.isEditing ? PantryCopy.editItem : PantryCopy.addItem)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(PantryCopy.cancel) { viewModel.sheet = nil }
                        .accessibilityIdentifier(AccessibilityID.pantryFormCancel)
                }
            }
            .onAppear {
                if form.trimmedName.isEmpty { nameFocused = true }
            }
        }
        .presentationDetents([.large])
    }

    /// Runs a save or delete; on success reloads the list and closes the sheet explicitly, both
    /// through the item binding and `dismiss`, so it closes in every presentation style (iPad).
    private func finish(_ action: @escaping () async -> Bool) {
        nameFocused = false
        Task {
            guard await action() else { return }
            await viewModel.sheetChangedPantry()
            viewModel.sheet = nil
            dismiss()
        }
    }

    private var bottomBar: some View {
        VStack(spacing: OMPSpacing.small) {
            if !form.canSave && !form.isSaving {
                Text(PantryCopy.saveNeedsAmount)
                    .font(OMPFont.disclaimer)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(PantryCopy.save) { finish { await form.save() } }
                .buttonStyle(.ompPrimary)
                .disabled(!form.canSave)
                .accessibilityIdentifier(AccessibilityID.pantryFormSave)
            if form.isEditing {
                Button(role: .destructive) {
                    finish { await form.delete() }
                } label: {
                    Text(PantryCopy.deleteItem)
                        .font(OMPFont.body)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .ompMinimumHitTarget()
                .accessibilityIdentifier(AccessibilityID.pantryFormDelete)
            }
        }
        .padding(OMPSpacing.medium)
        .frame(maxWidth: .infinity)
        .planBarBackground()
    }

    // MARK: Fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PantryCopy.name).font(OMPFont.reason.bold())
            TextField(
                PantryCopy.name,
                text: Binding(get: { form.name }, set: { form.typeName($0) }),
                prompt: Text(PantryCopy.namePrompt)
            )
            .font(OMPFont.body)
            .textFieldStyle(.roundedBorder)
            .focused($nameFocused)
            .autocorrectionDisabled()
            .accessibilityLabel(PantryCopy.name)
            .accessibilityIdentifier(AccessibilityID.pantryFormName)
        }
    }

    @ViewBuilder
    private var suggestions: some View {
        if !form.suggestions.isEmpty || form.offersAddAsTyped {
            VStack(alignment: .leading, spacing: OMPSpacing.small) {
                ForEach(Array(form.suggestions.prefix(6)), id: \.ingredientId) { candidate in
                    Button {
                        form.pick(candidate)
                        nameFocused = false
                    } label: {
                        Text(candidate.name)
                            .font(OMPFont.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .ompMinimumHitTarget()
                    .accessibilityIdentifier(AccessibilityID.pantryFormSuggestion(candidate.ingredientId.rawValue))
                }
                if form.offersAddAsTyped {
                    VStack(alignment: .leading, spacing: 2) {
                        Button {
                            form.keepAsTyped()
                            nameFocused = false
                        } label: {
                            Text(PantryCopy.addAsTyped(form.trimmedName))
                                .font(OMPFont.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .ompMinimumHitTarget()
                        .accessibilityIdentifier(AccessibilityID.pantryFormAsTyped)
                        Text(PantryCopy.addAsTypedNote)
                            .font(OMPFont.disclaimer)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(OMPSpacing.small)
            .ompCardBackground()
        }
    }

    private var amountRow: some View {
        AdaptiveStack(spacing: OMPSpacing.medium) {
            VStack(alignment: .leading, spacing: 4) {
                Text(PantryCopy.amount).font(OMPFont.reason.bold())
                TextField(PantryCopy.amount, text: $form.amountText)
                    .font(OMPFont.body)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .accessibilityLabel(PantryCopy.amount)
                    .accessibilityIdentifier(AccessibilityID.pantryFormAmount)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(PantryCopy.unit).font(OMPFont.reason.bold())
                Picker(PantryCopy.unit, selection: $form.unit) {
                    ForEach(form.units, id: \.self) { unit in
                        Text(PantryFormat.unitLabel(unit)).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(Color.primary)
                .accessibilityLabel(PantryCopy.unit)
                .accessibilityIdentifier(AccessibilityID.pantryFormUnit)
            }
        }
    }

    private var locationPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PantryCopy.whereLabel).font(OMPFont.reason.bold())
            Picker(PantryCopy.whereLabel, selection: $form.location) {
                ForEach(StorageLocation.allCases, id: \.self) { place in
                    Text(PantryCopy.location(place)).tag(place)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(PantryCopy.whereLabel)
            .accessibilityIdentifier(AccessibilityID.pantryFormLocation)
        }
    }

    private var useBy: some View {
        VStack(alignment: .leading, spacing: OMPSpacing.small) {
            Toggle(PantryCopy.useByDateLabel, isOn: $form.hasUseBy)
                .font(OMPFont.body)
                .accessibilityIdentifier(AccessibilityID.pantryFormUseByToggle)
            if form.hasUseBy {
                DatePicker(PantryCopy.useByDateLabel, selection: $form.useBy, displayedComponents: .date)
                    .labelsHidden()
                    .accessibilityIdentifier(AccessibilityID.pantryFormUseBy)
            }
        }
    }
}
