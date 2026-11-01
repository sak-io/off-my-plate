import Foundation

/// Household-wide settings (plan section 3.1).
public struct HouseholdSettings: Codable, Sendable, Hashable {
    /// Snack slots are off by default (AC-6.1, G5).
    public var snacksEnabled: Bool
    /// Used only for weekly counting (prompt caps, learning weeks), not plan dates (R8).
    public var weekStartsOn: Weekday

    public init(snacksEnabled: Bool = false, weekStartsOn: Weekday = .monday) {
        self.snacksEnabled = snacksEnabled
        self.weekStartsOn = weekStartsOn
    }
}

/// The household size chosen in onboarding is out of range (AC-1.3).
public enum HouseholdSizeError: Error, Sendable, Hashable {
    /// A negative adult or child count.
    case negativeCount
    /// Fewer than `Household.memberCountRange.lowerBound` members in total.
    case tooFew(total: Int)
    /// More than `Household.memberCountRange.upperBound` members in total.
    case tooMany(total: Int)
}

/// Everyone the app plans for, plus their hard rules (plan section 3.1).
public struct Household: Identifiable, Codable, Sendable, Hashable {
    public let id: HouseholdID
    /// All members, including soft-deleted ones (see `activeMembers`).
    public var members: [Member]
    /// Hard rules. Only the safety flows create them (ADR 0013).
    public var rules: [Rule]
    public var settings: HouseholdSettings
    public var createdAt: Date
    public var updatedAt: Date

    /// Allowed total member count (AC-1.3: at least 1; ASSUMPTION: at most 12).
    public static let memberCountRange: ClosedRange<Int> = 1...12

    public init(
        id: HouseholdID,
        members: [Member],
        rules: [Rule] = [],
        settings: HouseholdSettings = HouseholdSettings(),
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.members = members
        self.rules = rules
        self.settings = settings
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The household created by onboarding's "Who's eating?" step (AC-1.2, AC-1.3).
    ///
    /// Creates `adults` members labelled Adult 1...n with age band `.adult`, then `children`
    /// members labelled Child 1...n with age band `.child` (so portions follow AC-6.2 until the
    /// user edits them). Every member starts `unasked`; there are no rules yet.
    ///
    /// - Parameter makeMemberID: id factory, injectable so tests are deterministic.
    /// - Throws: `HouseholdSizeError` when a count is negative or the total is outside
    ///   `memberCountRange`.
    public static func onboarding(
        id: HouseholdID,
        adults: Int,
        children: Int,
        now: Date,
        makeMemberID: () -> MemberID = { MemberID.generate() }
    ) throws -> Household {
        guard adults >= 0, children >= 0 else { throw HouseholdSizeError.negativeCount }
        let total = adults + children
        if total < memberCountRange.lowerBound { throw HouseholdSizeError.tooFew(total: total) }
        if total > memberCountRange.upperBound { throw HouseholdSizeError.tooMany(total: total) }

        var members: [Member] = []
        for number in stride(from: 1, through: adults, by: 1) {
            members.append(
                Member(id: makeMemberID(), label: MemberLabel(role: .adult, number: number), ageBand: .adult))
        }
        for number in stride(from: 1, through: children, by: 1) {
            members.append(
                Member(id: makeMemberID(), label: MemberLabel(role: .child, number: number), ageBand: .child))
        }
        return Household(id: id, members: members, createdAt: now, updatedAt: now)
    }

    /// Members that have not been soft-deleted, in their stored order.
    public var activeMembers: [Member] {
        members.filter { !$0.isDeleted }
    }

    /// The member with `id`, including a soft-deleted one.
    public func member(_ id: MemberID) -> Member? {
        members.first { $0.id == id }
    }

    /// The hard rules that protect `memberID`: their own rules plus household-scope rules.
    public func rules(covering memberID: MemberID) -> [Rule] {
        rules.filter { $0.scope.covers(memberID) }
    }

    /// The label for a new member of `role` (Settings -> Household, AC-3.2): one more than the
    /// highest number used so far for that role, counting deleted members so a label is never
    /// reused.
    public func nextLabel(for role: MemberRole) -> MemberLabel {
        let highest = members.filter { $0.label.role == role }.map(\.label.number).max() ?? 0
        return MemberLabel(role: role, number: highest + 1)
    }
}
