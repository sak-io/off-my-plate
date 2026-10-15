/// Why the safety gate refuses to issue a planning clearance (ADR 0007; plan section 4.1).
///
/// The UI uses the member ids to say who still needs an answer (C-080, C-081). The gate
/// itself (`SafetyGate.evaluate`, `SafetyClearance`) is task T08.
public enum GateRefusal: Error, Codable, Sendable, Hashable {
    /// These non-deleted members are `unasked` (AC-3.1, AC-3.2).
    case safetyUnanswered([MemberID])
    /// These members' safety answers are older than the re-confirmation period (G3).
    case reconfirmationDue([MemberID])

    /// The members the refusal is about.
    public var memberIDs: [MemberID] {
        switch self {
        case .safetyUnanswered(let ids), .reconfirmationDue(let ids):
            return ids
        }
    }
}
