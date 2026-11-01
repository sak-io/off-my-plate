/// A record or blob could not be written or read (ADR 0003).
///
/// Reading never guesses: an unknown enum value or a half-written approval is an error, not a
/// silently dropped rule or a silently "approved" plan. Messages carry field names and enum raw
/// values only, never user-entered text.
public enum PersistenceError: Error, Sendable, Hashable {
    /// An entity (or a nested id, such as a meal's) had an empty identifier; empty ids are never
    /// written to storage (same contract as `EntityID`'s Codable).
    case emptyIdentifier(entity: String)
    /// A stored raw value does not map to a domain value (unknown enum case, bad date).
    case invalidValue(entity: String, field: String, value: String)
    /// A plan record has some but not all approval columns.
    case incompleteApproval(planId: String)
    /// The plan content blob has no `version` field or is not JSON.
    case unreadablePlanContent(planId: String)
    /// The plan content blob was written by a newer app version.
    case unsupportedPlanContentVersion(Int)
    /// The cook-log deductions blob has no `version` field or is not JSON.
    case unreadableDeductions(cookLogId: String)
    /// The cook-log deductions blob was written by a newer app version.
    case unsupportedDeductionsVersion(Int)
}
