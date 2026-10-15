import Foundation
import OMPDomain

/// What the root safety gate needs to know about the current household (ADR 0007, AC-3.1).
///
/// Derived only from `SafetyGate.evaluate`, so the UI and the planner can never disagree.
public enum GateStatus: Sendable, Hashable {
    /// The household has not been loaded yet.
    case loading
    /// No household yet: onboarding (T22) has not run.
    case noHousehold
    /// Every non-deleted member has a confirmed, in-date safety answer.
    case clear
    /// These members have no usable safety answer: planning is blocked and the gate cover shows.
    case unanswered([MemberID])
    /// These members' answers are older than 180 days: new drafts are blocked (G3), but the
    /// cover does not show; the Plan tab shows a re-check card instead (T23).
    case reconfirmationDue([MemberID])
    /// The household could not be loaded (C-096).
    case loadFailed

    /// The status of `household` at `now` in `timeZone`.
    public static func evaluate(_ household: Household?, now: Date, timeZone: TimeZone) -> GateStatus {
        guard let household else { return .noHousehold }
        switch SafetyGate.evaluate(household, now: now, timeZone: timeZone) {
        case .success:
            return .clear
        case .failure(.safetyUnanswered(let ids)):
            return .unanswered(ids)
        case .failure(.reconfirmationDue(let ids)):
            return .reconfirmationDue(ids)
        }
    }

    /// Whether the full-screen gate cover must be shown (screens.md section 1: while any
    /// member is unasked).
    public var showsGateCover: Bool {
        if case .unanswered = self { return true }
        return false
    }

    /// Whether making new drafts is blocked, so the Plan tab shows its "!" badge.
    public var blocksPlanning: Bool {
        switch self {
        case .unanswered, .reconfirmationDue: return true
        case .loading, .noHousehold, .clear, .loadFailed: return false
        }
    }

    /// How many members block planning (0 unless unanswered or due).
    public var blockedMemberCount: Int {
        switch self {
        case .unanswered(let ids), .reconfirmationDue(let ids): return ids.count
        case .loading, .noHousehold, .clear, .loadFailed: return 0
        }
    }

    /// A short, data-free name for logs.
    var logName: String {
        switch self {
        case .loading: return "loading"
        case .noHousehold: return "noHousehold"
        case .clear: return "clear"
        case .unanswered: return "unanswered"
        case .reconfirmationDue: return "reconfirmationDue"
        case .loadFailed: return "loadFailed"
        }
    }
}
