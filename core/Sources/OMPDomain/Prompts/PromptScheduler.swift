import Foundation

/// The kind of a contextual card (plan section 7, UX D4).
public enum PromptKind: Sendable, Hashable {
    /// A safety question or notice. Always first and exempt from caps and cooldowns.
    case safety
    /// "Do any of the kids take lunch to school?" (AC-7.1, U11).
    case lunchbox
    /// A reflect-back card for a proposed soft fact (AC-12.2).
    case reflectBack(FactKey)
}

/// A card that could be shown now. The caller decides which cards are relevant at this moment
/// (for example the lunchbox card only when a lunch slot is opened in a household with
/// children, AC-7.1); the scheduler decides which one, if any, is shown.
///
/// Build candidates only through the factories (`.lunchbox`, `.safety(_:)`, `.reflectBack(_:)`):
/// the initializer is internal so that a candidate's id prefix always matches its kind
/// (`safety:`, `reflect:`, `lunchbox`), which is how past shows are classified for the caps.
public struct PromptCandidate: Sendable, Hashable {
    public let id: PromptID
    public let kind: PromptKind

    init(id: PromptID, kind: PromptKind) {
        precondition(PromptScheduler.kind(ofPromptID: id.rawValue) == PromptScheduler.kind(of: kind),
            "Prompt id '\(id.rawValue)' does not match its kind")
        self.id = id
        self.kind = kind
    }

    /// The lunchbox prompt (one id, so its state is shared across slots).
    public static let lunchbox = PromptCandidate(id: PromptScheduler.lunchboxPromptID, kind: .lunchbox)

    /// A safety card. Its id is `"safety:" + name` (for example `"safety:member-2"`), so past
    /// safety shows are never counted against the weekly cap.
    public static func safety(_ name: String) -> PromptCandidate {
        PromptCandidate(id: PromptID(PromptScheduler.safetyPrefix + name), kind: .safety)
    }

    /// The reflect-back card for a fact.
    public static func reflectBack(_ key: FactKey) -> PromptCandidate {
        PromptCandidate(id: PromptScheduler.reflectBackPromptID(for: key), kind: .reflectBack(key))
    }

    /// Reflect-back candidates for every `proposed`, not suppressed fact, sorted by id.
    public static func reflectBacks(from facts: [Fact]) -> [PromptCandidate] {
        facts
            .filter { $0.status == .proposed && !$0.suppressed }
            .map { reflectBack($0.key) }
            .sorted { $0.id < $1.id }
    }
}

/// The answer on the lunchbox card (U11).
public enum LunchboxPromptAnswer: String, CaseIterable, Codable, Sendable, Hashable {
    /// Opens the lunchbox setup; never asked again.
    case yes
    /// An answer, not a dismissal: never asked again (editable in Household).
    case no
    /// The skip: starts the 14-day cooldown (AC-7.3).
    case notNow
}

/// Picks the one card to show now (AC-7.1, AC-7.3, AC-7.4, AC-12.2). Pure: every input,
/// including the instant and the time zone, is passed in (ADR 0005).
///
/// Rules, in order:
/// 1. Safety cards come first and are exempt from every cap and cooldown.
/// 2. Only one card is visible at a time; a non-safety card already shown this ISO week and
///    not yet answered or dismissed stays the visible one.
/// 3. A non-safety card that was answered is never shown again (a reflect-back card only
///    returns in a later week, when the learner re-proposed its fact after "Not really");
///    one dismissed ("Not now") cools down for 14 days.
/// 4. At most 3 different non-safety cards are shown per ISO week.
/// 5. At most 1 reflect-back card is shown per ISO week.
/// 6. Otherwise the lunchbox card comes before reflect-back cards; ties break by id.
public enum PromptScheduler {
    public static let weeklyNonSafetyCap = 3
    public static let weeklyReflectBackCap = 1
    public static let cooldownDays = 14

    public static let lunchboxPromptID: PromptID = "lunchbox"
    static let reflectBackPrefix = "reflect:"

    public static func reflectBackPromptID(for key: FactKey) -> PromptID {
        PromptID(reflectBackPrefix + FactLearner.stableID(for: key).rawValue)
    }

    /// The single card to show now, or `nil`.
    ///
    /// - Parameters:
    ///   - candidates: the cards relevant at this moment.
    ///   - states: the stored state of every prompt ever shown (any order; unknown ids are
    ///     treated as never shown).
    ///   - now: the current instant.
    ///   - timeZone: decides the ISO week of `now` and of past shows.
    public static func next(
        candidates: [PromptCandidate], states: [PromptState], now: Date, timeZone: TimeZone
    ) -> PromptCandidate? {
        if let safety = candidates.filter({ $0.kind == .safety }).min(by: { $0.id < $1.id }) {
            return safety
        }

        var stateByID: [PromptID: PromptState] = [:]
        for state in states { stateByID[state.promptId] = state }
        let thisWeek = ISOWeek(containing: now, in: timeZone)

        func shownThisWeek(_ state: PromptState) -> Bool {
            guard let shown = state.lastShownAt else { return false }
            return ISOWeek(containing: shown, in: timeZone) == thisWeek
        }
        func isOpen(_ state: PromptState) -> Bool {
            guard let shown = state.lastShownAt, shownThisWeek(state) else { return false }
            if let answered = state.answeredAt, answered >= shown { return false }
            if let dismissed = state.dismissedAt, dismissed >= shown { return false }
            return true
        }
        func isReflectBack(_ id: PromptID) -> Bool {
            id.rawValue.hasPrefix(reflectBackPrefix)
        }

        let nonSafety = candidates.filter { $0.kind != .safety }.sorted { lhs, rhs in
            let lr = rank(lhs.kind)
            let rr = rank(rhs.kind)
            return lr != rr ? lr < rr : lhs.id < rhs.id
        }

        // Rule 2: a card that is still open this week stays the visible one.
        if let open = nonSafety.first(where: { stateByID[$0.id].map(isOpen) ?? false }) {
            return open
        }

        // Shows this week, counted per prompt (safety prompts are exempt from the cap).
        let nonSafetyShown =
            stateByID.values
            .filter { shownThisWeek($0) && !$0.promptId.rawValue.hasPrefix(safetyPrefix) }
            .map(\.promptId)
        guard nonSafetyShown.count < weeklyNonSafetyCap else { return nil }
        let reflectBacksShown = nonSafetyShown.filter(isReflectBack).count

        for candidate in nonSafety {
            if let state = stateByID[candidate.id] {
                if let answered = state.answeredAt {
                    // Lunchbox: Yes and No are final (U11). Reflect-back: a candidate exists
                    // only while its fact is proposed, so an answer from an earlier week means
                    // the learner re-proposed it after "Not really"; one from this week is
                    // stale until the learner has run.
                    guard case .reflectBack = candidate.kind,
                        ISOWeek(containing: answered, in: timeZone) < thisWeek
                    else { continue }
                }
                if let dismissed = state.dismissedAt, now.timeIntervalSince(dismissed) < cooldownSeconds {
                    continue
                }
            }
            if case .reflectBack = candidate.kind, reflectBacksShown >= weeklyReflectBackCap { continue }
            return candidate
        }
        return nil
    }

    // MARK: State transitions

    /// Records that the card was shown at `now`.
    public static func markShown(_ state: PromptState, now: Date) -> PromptState {
        var copy = state
        copy.lastShownAt = now
        return copy
    }

    /// Records a lunchbox answer (U11): Yes and No are answers; Not now starts the cooldown.
    public static func recordLunchbox(_ answer: LunchboxPromptAnswer, on state: PromptState, now: Date) -> PromptState {
        var copy = state
        switch answer {
        case .yes, .no: copy.answeredAt = now
        case .notNow: copy.dismissedAt = now
        }
        return copy
    }

    /// Records a reflect-back answer (the fact itself changes through a
    /// `.reflectBackAnswered` learning event and `FactLearner.update`).
    public static func recordReflectBack(_ answer: ReflectBackAnswer, on state: PromptState, now: Date) -> PromptState {
        var copy = state
        copy.answeredAt = now
        return copy
    }

    /// Ids of safety prompts start with this prefix by convention, so a past safety show is
    /// never counted against the weekly cap.
    public static let safetyPrefix = "safety:"

    // MARK: Private

    private static let cooldownSeconds = Double(cooldownDays) * 86_400

    /// The coarse class of a prompt id, from its prefix: 0 safety, 1 lunchbox, 2 reflect-back,
    /// -1 unknown.
    static func kind(ofPromptID raw: String) -> Int {
        if raw.hasPrefix(safetyPrefix) { return 0 }
        if raw == lunchboxPromptID.rawValue { return 1 }
        if raw.hasPrefix(reflectBackPrefix) { return 2 }
        return -1
    }

    static func kind(of kind: PromptKind) -> Int {
        rank(kind)
    }

    private static func rank(_ kind: PromptKind) -> Int {
        switch kind {
        case .safety: return 0
        case .lunchbox: return 1
        case .reflectBack: return 2
        }
    }
}
