import Foundation

/// Proof that the safety gate passed for one household at one instant (ADR 0007).
///
/// Only `SafetyGate` can create one: the initialiser is `fileprivate` and this type lives in
/// the same file as the gate (`scripts/lint-safety.sh`, T12, fails if `SafetyClearance(`
/// appears in any other file). It is deliberately **not** `Codable`, because a decoder would be
/// a second way to construct one.
///
/// The clearance carries an immutable snapshot of the household as the gate saw it. Every
/// planner entry point takes a clearance and plans **only from this snapshot**, so clearing
/// household A and then planning for household B (or for a household edited after the check)
/// is impossible.
public struct SafetyClearance: Sendable, Hashable {
    /// The household the gate cleared.
    public let householdID: HouseholdID
    /// The non-deleted members at evaluation time, in stored order. Every one of them had a
    /// confirmed, in-date safety answer.
    public let members: [Member]
    /// The household's hard rules at evaluation time (member and household scope).
    public let rules: [Rule]
    /// The household settings at evaluation time (snack slots and so on).
    public let settings: HouseholdSettings
    /// The instant the gate evaluated.
    public let issuedAt: Date

    fileprivate init(household: Household, issuedAt: Date) {
        self.householdID = household.id
        self.members = household.activeMembers
        self.rules = household.rules.filter { $0.kind == .hard }
        self.settings = household.settings
        self.issuedAt = issuedAt
    }

    /// The hard rules that protect `memberID` in this snapshot: their own plus household scope.
    public func rules(covering memberID: MemberID) -> [Rule] {
        rules.filter { $0.scope.covers(memberID) }
    }

    /// Whether `household` still has exactly the safety-relevant content this clearance was
    /// issued for (same id, active members, hard rules and settings). The household
    /// fingerprint of ADR 0007, compared structurally: a stale clearance must be re-evaluated.
    public func matches(_ household: Household) -> Bool {
        household.id == householdID && household.activeMembers == members
            && household.rules.filter({ $0.kind == .hard }) == rules && household.settings == settings
    }
}

/// The domain-layer safety gate (ADR 0007; plan section 4.1; AC-3.1, G3).
///
/// Planning is refused while any non-deleted member has no confirmed safety answer, or while a
/// member's answer is older than `reconfirmationPeriodDays`. Deleted members never block.
public enum SafetyGate {
    /// Answers older than this many whole calendar days must be re-confirmed (G3). An answer
    /// confirmed exactly 180 days ago is still valid; 181 days ago is due.
    public static let reconfirmationPeriodDays = 180

    /// Evaluates `household` at `now`, using `timeZone` to turn instants into calendar days.
    ///
    /// - Returns: a clearance, or `.safetyUnanswered(ids)` when any non-deleted member is
    ///   unanswered (this takes precedence), otherwise `.reconfirmationDue(ids)` when any
    ///   member's answer is overdue. Ids are in the household's stored member order.
    public static func evaluate(_ household: Household, now: Date, timeZone: TimeZone)
        -> Result<SafetyClearance, GateRefusal>
    {
        let unanswered = membersNeedingAnswer(in: household)
        if !unanswered.isEmpty {
            return .failure(.safetyUnanswered(unanswered))
        }
        let today = LocalDate(now, in: timeZone)
        let due = membersDueForReconfirmation(in: household, today: today, timeZone: timeZone)
        if !due.isEmpty {
            return .failure(.reconfirmationDue(due))
        }
        return .success(SafetyClearance(household: household, issuedAt: now))
    }

    /// Evaluates `household` at the clock's current instant, in the clock's time zone.
    public static func evaluate(_ household: Household, clock: some DomainClock)
        -> Result<SafetyClearance, GateRefusal>
    {
        evaluate(household, now: clock.now, timeZone: clock.timeZone)
    }

    /// Whether an existing draft may be approved (UX U4): refused while any non-deleted member
    /// is unanswered; an overdue re-confirmation does **not** block approval (G3 blocks only
    /// new drafts).
    ///
    /// - Returns: `nil` when approval is allowed, otherwise `.safetyUnanswered(ids)`.
    public static func approvalRefusal(for household: Household) -> GateRefusal? {
        let unanswered = membersNeedingAnswer(in: household)
        return unanswered.isEmpty ? nil : .safetyUnanswered(unanswered)
    }

    /// Non-deleted members without a usable safety answer: `unasked`, or (failing closed,
    /// TR-3) `confirmedNone`/`stated` with no `safetyConfirmedAt`.
    public static func membersNeedingAnswer(in household: Household) -> [MemberID] {
        household.activeMembers.filter(needsAnswer).map(\.id)
    }

    /// Non-deleted, answered members whose answer is more than `reconfirmationPeriodDays`
    /// calendar days before `today` (days counted in `timeZone`).
    public static func membersDueForReconfirmation(
        in household: Household, today: LocalDate, timeZone: TimeZone
    ) -> [MemberID] {
        household.activeMembers.filter { member in
            guard !needsAnswer(member), let confirmedAt = member.safetyConfirmedAt else { return false }
            let confirmedDay = LocalDate(confirmedAt, in: timeZone)
            return today.daysSince(confirmedDay) > reconfirmationPeriodDays
        }.map(\.id)
    }

    private static func needsAnswer(_ member: Member) -> Bool {
        switch member.safetyStatus {
        case .unasked:
            return true
        case .confirmedNone, .stated:
            return member.safetyConfirmedAt == nil
        }
    }
}
