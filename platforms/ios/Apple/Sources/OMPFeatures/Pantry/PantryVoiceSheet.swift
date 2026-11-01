import OMPCapture
import OMPDomain
import OMPUI
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// S-22 (listening, then the confirm card) and S-23 (voice unavailable). Voice is confirm-to-save:
/// nothing is stored until the user taps the confirm button (AC-9.4); with voice off, denied or
/// unsupported the sheet explains why and offers "Type instead" (AC-9.5).
struct PantryVoiceSheet: View {
    let viewModel: PantryViewModel
    @State private var model: PantryVoiceModel
    @Environment(\.openURL) private var openURL

    init(viewModel: PantryViewModel, backend: any PantryBackend) {
        self.viewModel = viewModel
        _model = State(initialValue: PantryVoiceModel(backend: backend, speech: viewModel.speech))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OMPSpacing.medium) {
                    stateContent
                }
                .frame(maxWidth: OMPMetrics.readableMaxWidth, alignment: .leading)
                .padding(OMPSpacing.medium)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier(AccessibilityID.voiceSheet)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(PantryCopy.cancel) {
                        model.cancel()
                        viewModel.sheet = nil
                    }
                    .accessibilityIdentifier(AccessibilityID.voiceCancel)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await model.start() }
        .onDisappear { model.cancel() }
        .onChange(of: model.savedCount) { _, count in
            guard let count else { return }
            Task {
                await viewModel.sheetChangedPantry()
                viewModel.toast = PantryCopy.voiceAdded(count)
                viewModel.sheet = nil
            }
        }
    }

    private var title: String {
        switch model.state {
        case .idle, .listening: return PantryCopy.listening
        case .confirm: return PantryCopy.confirmTitle
        case .nothingUnderstood: return PantryCopy.addItem
        case .unavailable: return PantryCopy.speak
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch model.state {
        case .idle, .listening:
            listening
        case .confirm:
            confirm
        case .nothingUnderstood:
            nothingUnderstood
        case .unavailable(let reason):
            unavailable(reason)
        }
    }

    // MARK: S-22 listening

    private var listening: some View {
        VStack(alignment: .leading, spacing: OMPSpacing.medium) {
            // A static symbol: nothing moves, so Reduce Motion needs no special case.
            Label(PantryCopy.listening, systemImage: OMPSymbol.listening)
                .font(OMPFont.sectionTitle.bold())
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier(AccessibilityID.voiceListening)
            if !model.transcript.isEmpty {
                Text("“\(model.transcript)”")
                    .font(OMPFont.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.voiceTranscript)
            }
            Text(PantryCopy.listeningHint)
                .font(OMPFont.reason)
                .fixedSize(horizontal: false, vertical: true)
            Button(PantryCopy.done) { model.stopListening() }
                .buttonStyle(.ompPrimary)
                .accessibilityIdentifier(AccessibilityID.voiceDone)
        }
    }

    // MARK: S-22 confirm

    private var confirm: some View {
        VStack(alignment: .leading, spacing: OMPSpacing.medium) {
            if model.wasInterrupted {
                Text(PantryCopy.interrupted).font(OMPFont.reason)
            }
            VStack(alignment: .leading, spacing: OMPSpacing.small) {
                ForEach(model.drafts) { draft in
                    draftRow(draft)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.voiceConfirmCard)
            if !model.unparsedText.isEmpty {
                InlineCard(title: PantryCopy.didntCatch(model.unparsedText), systemImage: OMPSymbol.warning) {
                    Button(PantryCopy.addByHand) {
                        model.cancel()
                        viewModel.replaceSheet(with: .add(model.byHandPrefill))
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.primary)
                    .ompMinimumHitTarget()
                    .accessibilityIdentifier(AccessibilityID.voiceAddByHand)
                }
                .accessibilityIdentifier(AccessibilityID.voiceUnparsed)
            }
            if let message = model.errorMessage {
                InlineCard(title: message, systemImage: OMPSymbol.warning)
                    .accessibilityIdentifier(AccessibilityID.voiceError)
            }
            Button(model.confirmTitle) { Task { await model.confirm() } }
                .buttonStyle(.ompPrimary)
                .disabled(!model.canConfirm)
                .accessibilityIdentifier(AccessibilityID.voiceConfirmAdd)
        }
    }

    private func draftRow(_ draft: VoiceDraft) -> some View {
        VStack(alignment: .leading, spacing: OMPSpacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: OMPSpacing.small) {
                Text(rowText(draft))
                    .font(OMPFont.mealName)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(AccessibilityID.voiceItem(draft.id))
                if draft.kind == .add {
                    Button(draft.isEditing ? PantryCopy.doneEditing : PantryCopy.edit) {
                        model.toggleEditing(draft.id)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.primary)
                    .ompMinimumHitTarget()
                    .accessibilityIdentifier(AccessibilityID.voiceItemEdit(draft.id))
                }
            }
            if draft.needsCheck {
                StatusLabel(PantryCopy.notUnderstoodEdit, systemImage: OMPSymbol.warning)
                    .font(OMPFont.reason)
            }
            if draft.isEditing {
                editor(draft)
            }
        }
        .padding(OMPSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ompCardBackground()
    }

    private func rowText(_ draft: VoiceDraft) -> String {
        switch draft.kind {
        case .add:
            let amount = PantryFormat.parseAmount(draft.amountText) ?? 0
            return "\(draft.name) · \(PantryFormat.amount(amount, draft.unit))"
        case .markOut: return PantryCopy.setToZero(draft.name)
        case .remove: return PantryCopy.removeFromPantry(draft.name)
        }
    }

    private func editor(_ draft: VoiceDraft) -> some View {
        VStack(alignment: .leading, spacing: OMPSpacing.small) {
            AdaptiveStack(spacing: OMPSpacing.medium) {
                TextField(
                    PantryCopy.amount,
                    text: Binding(get: { draft.amountText }, set: { model.setAmount(draft.id, $0)})
                )
                .font(OMPFont.body)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .accessibilityLabel(PantryCopy.amount)
                .accessibilityIdentifier(AccessibilityID.voiceItemAmount(draft.id))
                Picker(
                    PantryCopy.unit,
                    selection: Binding(get: { draft.unit }, set: { model.setUnit(draft.id, $0) })
                ) {
                    ForEach(PantryFormat.units(including: draft.unit), id: \.self) { unit in
                        Text(PantryFormat.unitLabel(unit)).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(Color.primary)
                .accessibilityLabel(PantryCopy.unit)
            }
            Button(PantryCopy.skip) { model.skip(draft.id) }
                .buttonStyle(.bordered)
                .tint(Color.primary)
                .ompMinimumHitTarget()
                .accessibilityIdentifier(AccessibilityID.voiceItemSkip(draft.id))
        }
    }

    // MARK: Nothing understood (C-131)

    private var nothingUnderstood: some View {
        VStack(alignment: .leading, spacing: OMPSpacing.medium) {
            Text(model.transcript.isEmpty ? PantryCopy.nothingHeard : PantryCopy.nothingUnderstood(model.transcript))
                .font(OMPFont.body)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(AccessibilityID.voiceNothing)
            AdaptiveStack(spacing: OMPSpacing.small) {
                Button(PantryCopy.tryAgainVoice) { Task { await model.start() } }
                    .buttonStyle(.ompPrimary)
                    .accessibilityIdentifier(AccessibilityID.voiceTryAgain)
                Button(PantryCopy.typeInstead) {
                    model.cancel()
                    viewModel.replaceSheet(with: .add(model.byHandPrefill))
                }
                .buttonStyle(.bordered)
                .tint(Color.primary)
                .ompMinimumHitTarget()
                .accessibilityIdentifier(AccessibilityID.voiceTypeInstead)
            }
        }
    }

    // MARK: S-23 voice unavailable

    private func unavailable(_ reason: SpeechAvailability) -> some View {
        let denied = reason == .permissionDenied
        return VStack(alignment: .leading, spacing: OMPSpacing.medium) {
            Text(denied ? PantryCopy.voiceDenied : PantryCopy.voiceUnavailable)
                .font(OMPFont.body)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(denied ? AccessibilityID.voiceDenied : AccessibilityID.voiceUnavailable)
            AdaptiveStack(spacing: OMPSpacing.small) {
                #if canImport(UIKit)
                if denied {
                    Button(PantryCopy.openSettings) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.primary)
                    .ompMinimumHitTarget()
                    .accessibilityIdentifier(AccessibilityID.voiceOpenSettings)
                }
                #endif
                Button(PantryCopy.typeInsteadShort) {
                    viewModel.replaceSheet(with: .add(nil))
                }
                .buttonStyle(.bordered)
                .tint(Color.primary)
                .ompMinimumHitTarget()
                .accessibilityIdentifier(AccessibilityID.voiceTypeInstead)
            }
        }
    }
}
