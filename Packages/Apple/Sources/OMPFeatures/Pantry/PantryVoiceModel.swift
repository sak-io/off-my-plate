import Foundation
import Observation
import OMPCapture
import OMPDomain
import OMPServices

/// One thing the user said, on the confirm card (S-22). Editable before it is saved.
public struct VoiceDraft: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case add, markOut, remove
    }

    public let id: Int
    public let kind: Kind
    public let spoken: SpokenPantryItem
    /// The ingredient's name as the taxonomy spells it.
    public let name: String
    public var amountText: String
    public var unit: MeasureUnit
    public var isEditing = false
    /// The match is not confident: the card asks the user to check it.
    public var needsCheck: Bool { !spoken.isConfident }
}

/// The speak sheet (S-22, S-23): listen, show what was understood, save only after the user
/// confirms (AC-9.4). Nothing reaches the pantry before `confirm()`.
@MainActor
@Observable
public final class PantryVoiceModel {
    public enum State: Equatable, Sendable {
        /// Before `start()`.
        case idle
        case listening
        /// Items understood; waiting for the user's confirmation.
        case confirm
        /// Nothing understood (C-131).
        case nothingUnderstood
        /// Voice cannot run (S-23: C-134 denied, C-135 otherwise).
        case unavailable(SpeechAvailability)
    }

    private let backend: any PantryBackend
    private let speech: (any SpeechCapture)?
    private var listeningTask: Task<Void, Never>?

    public private(set) var state: State = .idle
    /// The live or final transcript.
    public private(set) var transcript = ""
    public private(set) var drafts: [VoiceDraft] = []
    /// The pieces of the transcript that were not understood, joined.
    public private(set) var unparsedText = ""
    /// The recogniser stopped early (call, backgrounding, error): C-132.
    public private(set) var wasInterrupted = false
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    /// Set when the user's confirmation was saved; the sheet then closes.
    public private(set) var savedCount: Int?

    public init(backend: any PantryBackend, speech: (any SpeechCapture)?) {
        self.backend = backend
        self.speech = speech
    }

    // MARK: Listening

    /// Starts listening, asking for permission just in time (AC-9.5).
    public func start() async {
        guard state == .idle || state == .nothingUnderstood || state == .confirm else { return }
        guard let speech else {
            state = .unavailable(.recognizerUnavailable)
            return
        }
        var availability = speech.availability()
        if availability == .needsPermission { availability = await speech.requestAuthorization() }
        guard availability == .available else {
            state = .unavailable(availability)
            return
        }
        transcript = ""
        drafts = []
        unparsedText = ""
        wasInterrupted = false
        errorMessage = nil
        do {
            let stream = try speech.start()
            state = .listening
            listeningTask = Task { [weak self] in
                var failed = false
                do {
                    for try await part in stream {
                        self?.transcript = part.text
                    }
                } catch {
                    failed = true
                    let kind = OMPLog.errorKind(error)
                    OMPLog.app.error("Pantry voice failed: \(kind, privacy: .public)")
                }
                self?.finishListening(interrupted: failed)
            }
        } catch {
            state = .unavailable(speech.availability())
        }
    }

    /// "Done": stops listening; the final transcript then arrives and the card appears.
    public func stopListening() {
        speech?.stop()
    }

    /// "Cancel" or the sheet going away.
    public func cancel() {
        speech?.stop()
        listeningTask?.cancel()
        listeningTask = nil
    }

    /// Parses what was heard (nothing is saved).
    func finishListening(interrupted: Bool) {
        listeningTask = nil
        wasInterrupted = interrupted
        let result = backend.parseSpoken(transcript)
        var built: [VoiceDraft] = []
        for command in result.commands {
            switch command {
            case .add(let items): built += make(items, .add, from: built.count)
            case .markOut(let items): built += make(items, .markOut, from: built.count)
            case .remove(let items): built += make(items, .remove, from: built.count)
            case .openApprovalSheet: break
            }
        }
        drafts = built
        unparsedText = result.unparsedText
        state = built.isEmpty ? .nothingUnderstood : .confirm
    }

    private func make(_ items: [SpokenPantryItem], _ kind: VoiceDraft.Kind, from start: Int) -> [VoiceDraft] {
        items.enumerated().map { offset, spoken in
            let defaults = backend.defaults(for: spoken.match.ingredientId)
            // A bare number is a count (pieces); no amount at all means one in the default unit,
            // exactly as the service stores it.
            let unit = spoken.qty == nil ? (defaults?.unit ?? .piece) : (spoken.unit ?? .piece)
            let amount = spoken.qty.map { PantryFormat.number($0) } ?? "1"
            return VoiceDraft(
                id: start + offset, kind: kind, spoken: spoken, name: defaults?.name ?? spoken.match.name,
                amountText: amount, unit: unit)
        }
    }

    // MARK: Editing the card

    public func toggleEditing(_ id: Int) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[index].isEditing.toggle()
    }

    public func setAmount(_ id: Int, _ text: String) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[index].amountText = text
    }

    public func setUnit(_ id: Int, _ unit: MeasureUnit) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[index].unit = unit
    }

    /// Drops one item from the card.
    public func skip(_ id: Int) {
        drafts.removeAll { $0.id == id }
        if drafts.isEmpty { state = .nothingUnderstood }
    }

    /// Whether every amount the card would add is valid.
    public var canConfirm: Bool {
        guard state == .confirm, !drafts.isEmpty, !isSaving else { return false }
        return drafts.allSatisfy { draft in
            draft.kind != .add || ((PantryFormat.parseAmount(draft.amountText) ?? 0) > 0)
        }
    }

    public var addCount: Int { drafts.filter { $0.kind == .add }.count }

    /// "Add n items" when the card only adds, else "Update pantry" (C-130a).
    public var confirmTitle: String {
        guard drafts.allSatisfy({ $0.kind == .add }) else { return PantryCopy.updatePantry }
        return drafts.count == 1 ? PantryCopy.addOneItem : PantryCopy.addItems(drafts.count)
    }

    /// "Add it by hand" / "Type instead": what the form starts with.
    public var byHandPrefill: PantryFormPrefill {
        PantryFormPrefill(name: unparsedText, transcript: transcript.isEmpty ? nil : transcript)
    }

    // MARK: Confirm

    /// The commands the user confirmed, with their edits.
    func confirmedCommands() -> [SpokenCommand] {
        drafts.map { draft in
            let amount = PantryFormat.parseAmount(draft.amountText)
            let item = SpokenPantryItem(
                spokenText: draft.spoken.spokenText, name: draft.spoken.name, qty: amount ?? draft.spoken.qty,
                unit: draft.unit, match: draft.spoken.match, isConfident: draft.spoken.isConfident)
            switch draft.kind {
            case .add: return SpokenCommand.add([item])
            case .markOut: return SpokenCommand.markOut([item])
            case .remove: return SpokenCommand.remove([item])
            }
        }
    }

    /// Saves what the user confirmed (the only way voice changes the pantry, AC-9.4).
    public func confirm() async {
        guard canConfirm else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let outcome = try await backend.confirmVoice(confirmedCommands())
            savedCount = outcome.added.count + outcome.markedOut.count + outcome.removed.count
            errorMessage = nil
        } catch {
            let kind = OMPLog.errorKind(error)
            OMPLog.app.error("Pantry voice save failed: \(kind, privacy: .public)")
            errorMessage = PantryCopy.saveFailed
        }
    }
}
