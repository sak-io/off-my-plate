import OMPDomain
import OMPUI
import SwiftUI

/// S-15: "Cooked {meal}?" (AC-9.6). Lists what the meal takes out of the pantry with an amount
/// the user can edit, and updates the pantry on the button. Presented by the Plan tab for an
/// approved meal only.
struct CookedSheet: View {
    @State private var model: CookedModel
    /// Closes the sheet without cooking.
    let onCancel: () -> Void
    /// The pantry was updated: the Plan tab reloads and shows the toast.
    let onFinished: () async -> Void

    init(
        backend: (any PantryBackend)?, plan: MealPlanID, meal: PlannedMealID, onCancel: @escaping () -> Void,
        onFinished: @escaping () async -> Void
    ) {
        _model = State(initialValue: CookedModel(backend: backend, plan: plan, meal: meal))
        self.onCancel = onCancel
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OMPSpacing.medium) {
                    content
                }
                .frame(maxWidth: OMPMetrics.readableMaxWidth, alignment: .leading)
                .padding(OMPSpacing.medium)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier(AccessibilityID.cookedSheet)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(PantryCopy.cancel, action: onCancel)
                        .accessibilityIdentifier(AccessibilityID.cookedCancel)
                }
            }
        }
        // Large only: the lines and the button must all be reachable without a half-height sheet.
        .presentationDetents([.large])
        .task { await model.load() }
        .onChange(of: model.didFinish) { _, finished in
            guard finished else { return }
            Task { await onFinished() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView(PantryCopy.loading)
                .accessibilityIdentifier(AccessibilityID.cookedLoading)
        case .failed(let message):
            Text(message)
                .font(OMPFont.body)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(AccessibilityID.cookedError)
        case .ready:
            ready
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: OMPSpacing.medium) {
            Text(PantryCopy.cookedTitle(model.mealTitle))
                .font(OMPFont.sectionTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(PantryCopy.cookedIntro)
                .font(OMPFont.body)
                .fixedSize(horizontal: false, vertical: true)
            if model.lines.isEmpty {
                Text(PantryCopy.noIngredients)
                    .font(OMPFont.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.cookedEmpty)
            }
            ForEach(model.lines) { line in
                CookedLineView(model: model, line: line)
            }
            if let message = model.errorMessage {
                InlineCard(title: message, systemImage: OMPSymbol.warning)
                    .accessibilityIdentifier(AccessibilityID.cookedError)
            }
            Button(PantryCopy.updatePantryCooked) { Task { await model.update() } }
                .buttonStyle(.ompPrimary)
                .disabled(!model.canUpdate)
                .accessibilityIdentifier(AccessibilityID.cookedUpdate)
        }
    }
}

/// One ingredient line: name, "{used} of {have}", "Will be 0", or "Not in your pantry".
/// Edit opens minus / plus buttons and a number field (explicit Buttons: a `Stepper` is not
/// reliably reachable by XCUITest).
struct CookedLineView: View {
    let model: CookedModel
    let line: CookedLine
    @State private var text: String

    init(model: CookedModel, line: CookedLine) {
        self.model = model
        self.line = line
        _text = State(initialValue: PantryFormat.number(line.amount))
    }

    var body: some View {
        let id = line.id
        VStack(alignment: .leading, spacing: OMPSpacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: OMPSpacing.small) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.name)
                        .font(OMPFont.mealName)
                    if let have = line.have {
                        Text(
                            PantryCopy.usedOf(
                                PantryFormat.amount(line.amount, line.unit), PantryFormat.amount(have, line.unit))
                        )
                        .font(OMPFont.reason)
                        .accessibilityIdentifier(AccessibilityID.cookedAmount(id))
                        if line.willBeZero {
                            Text(PantryCopy.willBeZero)
                                .font(OMPFont.reason.bold())
                                .accessibilityIdentifier(AccessibilityID.cookedZero(id))
                        }
                    } else {
                        Text(PantryCopy.notInPantry)
                            .font(OMPFont.reason)
                            .accessibilityIdentifier(AccessibilityID.cookedNone(id))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                if line.have != nil {
                    Button(line.isEditing ? PantryCopy.doneEditing : PantryCopy.edit) {
                        model.toggleEditing(id)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.primary)
                    .ompMinimumHitTarget()
                    .accessibilityLabel(PantryCopy.editLabel(line.name))
                    .accessibilityIdentifier(AccessibilityID.cookedEdit(id))
                }
            }
            if line.isEditing {
                editor(id)
            }
        }
        .padding(OMPSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ompCardBackground()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.cookedLine(id))
    }

    private func editor(_ id: String) -> some View {
        HStack(spacing: OMPSpacing.small) {
            Button {
                model.decrease(id)
            } label: {
                Image(systemName: "minus").frame(minWidth: 24)
            }
            .buttonStyle(.bordered)
            .tint(Color.primary)
            .ompMinimumHitTarget()
            .accessibilityLabel(PantryCopy.less(line.name))
            .accessibilityIdentifier(AccessibilityID.cookedLess(id))
            TextField(PantryCopy.amount, text: $text)
                .font(OMPFont.body)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .accessibilityLabel(PantryCopy.amount)
                .accessibilityIdentifier(AccessibilityID.cookedField(id))
                .onChange(of: text) { _, new in model.setAmount(id, text: new) }
            Button {
                model.increase(id)
            } label: {
                Image(systemName: "plus").frame(minWidth: 24)
            }
            .buttonStyle(.bordered)
            .tint(Color.primary)
            .ompMinimumHitTarget()
            .accessibilityLabel(PantryCopy.more(line.name))
            .accessibilityIdentifier(AccessibilityID.cookedMore(id))
        }
        .onChange(of: line.amount) { _, amount in
            // Plus and minus change the amount: keep the field in step (but not while typing).
            if PantryFormat.parseAmount(text) != amount { text = PantryFormat.number(amount) }
        }
    }
}
