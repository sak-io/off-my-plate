import Foundation

/// An optional age band for a member (tech section 5.1).
public enum AgeBand: String, CaseIterable, Codable, Sendable, Hashable {
    case infant
    case toddler
    case child
    case teen
    case adult
    case senior

    /// The default portion for this band (AC-6.2; plan section 5 step 6):
    /// adult, teen and senior 1.0; child 0.6; toddler and infant 0.4.
    public var defaultPortion: Double {
        switch self {
        case .adult, .teen, .senior: return 1.0
        case .child: return 0.6
        case .toddler, .infant: return 0.4
        }
    }
}

/// Whether a member's allergies and restrictions have been addressed (tech section 5.1, G3).
/// There is deliberately no "skipped" state.
public enum SafetyStatus: String, CaseIterable, Codable, Sendable, Hashable {
    /// Not asked yet. Any non-deleted `unasked` member blocks planning (AC-3.1).
    case unasked
    /// The user said this member must avoid nothing.
    case confirmedNone
    /// The user confirmed at least one hard rule that covers this member.
    case stated
}

/// Whether a member was created as an adult or a child, for the generated label.
public enum MemberRole: String, CaseIterable, Codable, Sendable, Hashable {
    case adult
    case child
}

/// A member's generated label, "Adult 1" or "Child 2" (AC-1.2).
///
/// Stored structurally rather than as English text: the core builds no user-facing strings
/// (ADR 0005), so the UI renders it through the String Catalog ("Adult %lld").
public struct MemberLabel: Codable, Sendable, Hashable {
    public var role: MemberRole
    /// 1-based number within the role.
    public var number: Int

    public init(role: MemberRole, number: Int) {
        self.role = role
        self.number = number
    }
}

/// A person the household cooks for (plan section 3.1).
///
/// Only existence and `safetyStatus` are required (AC-16.1); every other field is optional or
/// has a default. Hard restrictions are not stored here: they are `Rule`s on the household
/// (V6), so there is one source of truth.
public struct Member: Identifiable, Codable, Sendable, Hashable {
    public let id: MemberID
    public var label: MemberLabel
    public var name: String?
    public var ageBand: AgeBand?
    public var safetyStatus: SafetyStatus
    /// When the safety answer was last confirmed; the 180-day re-confirmation counts from it.
    public var safetyConfirmedAt: Date?
    public var needsSchoolLunch: Bool
    public var schoolDays: Set<Weekday>
    /// A per-member portion that replaces the age-band default (AC-6.2).
    public var portionOverride: Double?
    /// Soft delete (sync-ready, ADR 0015). A deleted member never blocks planning.
    public var deletedAt: Date?

    public init(
        id: MemberID,
        label: MemberLabel,
        name: String? = nil,
        ageBand: AgeBand? = nil,
        safetyStatus: SafetyStatus = .unasked,
        safetyConfirmedAt: Date? = nil,
        needsSchoolLunch: Bool = false,
        schoolDays: Set<Weekday> = [],
        portionOverride: Double? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.name = name
        self.ageBand = ageBand
        self.safetyStatus = safetyStatus
        self.safetyConfirmedAt = safetyConfirmedAt
        self.needsSchoolLunch = needsSchoolLunch
        self.schoolDays = schoolDays
        self.portionOverride = portionOverride
        self.deletedAt = deletedAt
    }

    /// Whether the member has been soft-deleted.
    public var isDeleted: Bool {
        deletedAt != nil
    }

    /// The portion this member gets by default (AC-6.2): the override if set, otherwise the
    /// age-band default, otherwise 1.0 (an unknown age band is treated as an adult portion).
    public var defaultPortion: Double {
        if let portionOverride {
            return portionOverride
        }
        return ageBand?.defaultPortion ?? 1.0
    }
}
