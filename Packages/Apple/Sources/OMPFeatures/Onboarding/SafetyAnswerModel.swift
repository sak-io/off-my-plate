import Foundation
import Observation
import OMPCapture
import OMPDomain
import OMPServices

/// One row of "To avoid" (S-02). Nothing here is saved until the user confirms (AC-2.3).
struct AvoidItem: Identifiable, Hashable, Sendable {
    enum Resolution: Hashable, Sendable {
        /// Maps to a catalog restriction.
        case restriction(RestrictionID)
        /// The parser could not map this text. The user must pick a restriction or remove it
        /// (AC-2.4); it never counts as "safe" and is never dropped silently.
        case unresolved(text: String)
    }

    let id: Int
    var resolution: Resolution
    /// Who it protects. `.household` is "Not sure who (everyone)" (G3, the safer reading).
    var scope: RuleScope
    /// Added by tapping a chip (so tapping the chip again removes it).
    let fromChip: Bool

    var restrictionID: RestrictionID? {
        if case .restriction(let id) = resolution { return id }
        return nil
    }

    var isUnresolved: Bool { restrictionID == nil }
}

/// One line of the S-02b summary.
struct SummaryRow: Identifiable, Hashable, Sendable {
    let id: Int
    /// "Adult 1", "Everyone", "Everyone else".
    let who: String
    /// Restriction labels, or empty for "Nothing to avoid".
    let items: [String]
}

/// State of the mic next to the text field.
enum VoiceState: Equatable, Sendable {
    case idle
    case listening
    /// Voice cannot run; text and chips still work (C-134, C-135).
    case unavailable(SpeechAvailability)
}

/// The safety question (S-02, S-02b and the gate-cover variant; AC-2.1-2.6, AC-3.2, G3).
///
/// Rules are only ever created by the services from catalog restrictions after the user's
/// explicit confirmation ("Yes, save this" or "No, ..."). This model never writes the household
/// itself, never skips the question and never marks anyone answered on its own.
@MainActor
@Observable
final class SafetyAnswerModel {
    enum Phase: Equatable { case entry, summary }

    /// Who the question is about.
    enum Subject {
        /// Onboarding: the whole household; the Who? menu lists these members.
        case household(members: [Member])
        /// A member added later or left unasked: the question is scoped to them (F4).
        case member(Member, householdMemberCount: Int)
    }

    let subject: Subject
    private let services: SafetyServices
    private let speech: (any SpeechCapture)?
    private let onFinished: @MainActor () async -> Void

    private(set) var items: [AvoidItem] = []
    private(set) var phase: Phase = .entry
    private(set) var isSaving = false
    var saveFailed = false
    var draftText = ""
    private(set) var voice: VoiceState = .idle
    var isConfirmingRemoveMember = false
    private var nextItemID = 0
    private var listeningTask: Task<Void, Never>?

    init(
        subject: Subject, services: SafetyServices, speech: (any SpeechCapture)?,
        onFinished: @escaping @MainActor () async -> Void
    ) {
        self.subject = subject
        self.services = services
        self.speech = speech
        self.onFinished = onFinished
    }

    // MARK: Derived state

    var restrictions: [Restriction] { services.restrictions }

    /// Members the Who? menu offers. Empty (menu hidden) for one person or the member variant.
    var whoOptions: [Member] {
        if case .household(let members) = subject, members.count > 1 { return members }
        return []
    }

    var subjectMember: Member? {
        if case .member(let member, _) = subject { return member }
        return nil
    }

    var hasUnresolved: Bool { items.contains { $0.isUnresolved } }

    /// "No, nobody" is disabled while the list has items (C-026).
    var canChooseNobody: Bool { items.isEmpty && !isSaving }

    /// Continue shows once an item exists and is enabled only when none is unresolved (C-025).
    var canContinue: Bool { !items.isEmpty && !hasUnresolved && !isSaving }

    /// "Added by mistake? Remove {name}" is offered only for the member variant, and never for
    /// the last member (a household keeps one, AC-1.3).
    var canRemoveSubject: Bool {
        if case .member(_, let count) = subject { return count > 1 }
        return false
    }

    func isChipSelected(_ id: RestrictionID) -> Bool {
        items.contains { $0.fromChip && $0.restrictionID == id }
    }

    func label(for id: RestrictionID) -> String {
        restrictions.first { $0.id == id }.map(SafetyCopy.label(for:)) ?? id.rawValue
    }

    func scopeLabel(_ scope: RuleScope) -> String {
        switch scope {
        case .household: return SafetyCopy.notSureWho
        case .member(let id): return whoOptions.first { $0.id == id }?.displayName ?? SafetyCopy.notSureWho
        }
    }

    /// The scope a new item starts with: the member in the member variant, else everyone.
    private var defaultScope: RuleScope {
        if case .member(let member, _) = subject { return .member(member.id) }
        return .household
    }

    // MARK: Editing the list

    func toggleChip(_ id: RestrictionID) {
        if let index = items.firstIndex(where: { $0.fromChip && $0.restrictionID == id }) {
            items.remove(at: index)
        } else {
            append(.restriction(id), fromChip: true)
        }
    }

    /// A vertical-axis text field inserts a newline on Return: treat that as "submit".
    func draftTextChanged() {
        if draftText.contains("\n") { submitText() }
    }

    /// Parses the typed or spoken text into rows (on Return, or after the mic stops).
    func submitText() {
        guard phase == .entry else { draftText = ""; return }
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        draftText = ""
        guard !text.isEmpty else { return }
        for candidate in services.parser.parse(text) {
            switch candidate {
            case .restriction(let id, _, _):
                // Only catalog restrictions exist on screen; an unknown id stays unresolved.
                if restrictions.contains(where: { $0.id == id }) {
                    append(.restriction(id), fromChip: false)
                } else {
                    append(.unresolved(text: id.rawValue), fromChip: false)
                }
            case .unmapped(let text, _):
                append(.unresolved(text: text), fromChip: false)
            }
        }
    }

    func setScope(_ scope: RuleScope, for itemID: Int) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].scope = scope
    }

    /// "Pick closest match" for an unresolved row. If the same restriction is already listed
    /// for the same scope, the row simply goes away.
    func resolve(_ itemID: Int, to restriction: RestrictionID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let scope = items[index].scope
        if items.contains(where: { $0.restrictionID == restriction && $0.scope == scope }) {
            items.remove(at: index)
        } else {
            items[index].resolution = .restriction(restriction)
        }
    }

    func remove(_ itemID: Int) {
        items.removeAll { $0.id == itemID }
    }

    private func append(_ resolution: AvoidItem.Resolution, fromChip: Bool) {
        let scope = defaultScope
        if case .restriction(let id) = resolution,
            items.contains(where: { $0.restrictionID == id && $0.scope == scope })
        {
            return
        }
        items.append(AvoidItem(id: nextItemID, resolution: resolution, scope: scope, fromChip: fromChip))
        nextItemID += 1
    }

    // MARK: Summary (S-02b)

    /// Continue: shows the per-person summary. Refused while any row is unresolved.
    func continueToSummary() {
        guard canContinue else { return }
        // A live microphone must not add rows behind the summary the user is checking.
        speech?.stop()
        listeningTask?.cancel()
        voice = .idle
        phase = .summary
    }

    /// "Change": back to the list with every row kept.
    func backToEntry() {
        phase = .entry
    }

    var summaryRows: [SummaryRow] {
        var rows: [SummaryRow] = []
        var covered = Set<MemberID>()
        var everyoneCovered = false
        func labels(_ scope: RuleScope) -> [String] {
            items.filter { $0.scope == scope }.compactMap { $0.restrictionID }.map(label(for:))
        }
        if case .member(let member, _) = subject {
            rows.append(SummaryRow(id: 0, who: member.displayName, items: labels(.member(member.id))))
            return rows
        }
        for (offset, member) in whoOptions.enumerated() {
            let mine = labels(.member(member.id))
            if !mine.isEmpty {
                covered.insert(member.id)
                rows.append(SummaryRow(id: offset, who: member.displayName, items: mine))
            }
        }
        let everyone = labels(.household)
        if !everyone.isEmpty {
            everyoneCovered = true
            rows.append(SummaryRow(id: 1_000, who: SafetyCopy.everyone, items: everyone))
        }
        let everyoneElseExists = !everyoneCovered && !covered.isEmpty && covered.count < whoOptions.count
        if everyoneElseExists {
            rows.append(SummaryRow(id: 2_000, who: SafetyCopy.everyoneElse, items: []))
        }
        return rows
    }

    /// The requests the services receive: resolved rows only, without duplicates.
    var ruleRequests: [RuleRequest] {
        var seen = Set<RuleRequest>()
        var requests: [RuleRequest] = []
        for item in items {
            guard let restriction = item.restrictionID else { continue }
            let request = RuleRequest(restriction: restriction, scope: item.scope)
            if seen.insert(request).inserted { requests.append(request) }
        }
        return requests
    }

    // MARK: Saving (the user's explicit confirmation)

    /// "No, nobody" (onboarding) or "No, nothing" (one member). Disabled while rows exist.
    func chooseNobody() async {
        guard canChooseNobody else { return }
        await save {
            switch self.subject {
            case .household:
                _ = try await self.services.safety.confirmNobodyAvoidsAnything()
            case .member(let member, _):
                try await self.confirmMember(member.id, requests: [])
            }
        }
    }

    /// "Yes, save this" on S-02b.
    func confirmSummary() async {
        guard phase == .summary, canContinue else { return }
        let requests = ruleRequests
        guard !requests.isEmpty else { return }
        await save {
            switch self.subject {
            case .household:
                _ = try await self.services.safety.confirmSafetyAnswers(requests)
            case .member(let member, _):
                try await self.confirmMember(member.id, requests: requests)
            }
        }
    }

    /// Member variant: adds the member's rules that are not already in force, then confirms.
    /// Re-running after a failure adds nothing twice. A member whose household-wide rules
    /// already cover them is confirmed as `stated` (confirmMemberAnswer), not "nothing".
    private func confirmMember(_ memberID: MemberID, requests: [RuleRequest]) async throws {
        let stored = try await services.household.household()
        let existing = stored?.rules(covering: memberID).map(\.restriction) ?? []
        for request in requests where !existing.contains(request.restriction) {
            try await services.safety.addRule(request)
        }
        let after = try await services.household.household()
        let covered = !(after?.rules(covering: memberID).isEmpty ?? true)
        if covered {
            try await services.safety.confirmMemberAnswer(for: memberID)
        } else {
            try await services.safety.confirmNothingToAvoid(for: memberID)
        }
    }

    /// Confirmed "Remove {name}" (C-034): removes the member; the gate clears if they were the
    /// last one waiting.
    func removeSubject() async {
        guard let member = subjectMember, canRemoveSubject else { return }
        await save { _ = try await self.services.household.removeMember(member.id) }
    }

    private func save(_ work: () async throws -> Void) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await work()
        } catch {
            let kind = OMPLog.errorKind(error)
            OMPLog.app.error("Saving the safety answer failed: \(kind, privacy: .public)")
            saveFailed = true
            return
        }
        await onFinished()
    }

    // MARK: Voice (T30)

    /// Mic button: starts or stops listening. When voice cannot run, `voice` says why and the
    /// text field and chips keep working.
    func micTapped() async {
        guard let speech else {
            voice = .unavailable(.recognizerUnavailable)
            return
        }
        if voice == .listening {
            speech.stop()
            return
        }
        var availability = speech.availability()
        if availability == .needsPermission { availability = await speech.requestAuthorization() }
        guard availability == .available else {
            voice = .unavailable(availability)
            return
        }
        do {
            let stream = try speech.start()
            voice = .listening
            listeningTask = Task { [weak self] in
                var last = ""
                do {
                    for try await transcript in stream {
                        last = transcript.text
                        self?.draftText = transcript.text
                    }
                } catch {
                    let kind = OMPLog.errorKind(error)
                    OMPLog.app.error("Voice capture failed: \(kind, privacy: .public)")
                }
                guard let self else { return }
                self.voice = .idle
                if !last.isEmpty { self.submitText() }
            }
        } catch {
            voice = .unavailable(speech.availability())
        }
    }

    /// Stops listening when the screen goes away.
    func viewDisappeared() {
        speech?.stop()
        listeningTask?.cancel()
    }

    /// "Type instead" / dismisses the unavailable notice.
    func dismissVoiceNotice() {
        if case .unavailable = voice { voice = .idle }
    }
}
