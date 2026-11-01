import Foundation

/// How strictly a rule applies. v1 has hard rules only; soft preferences are `Fact`s
/// (ADR 0013), so inference can never produce a `Rule`.
public enum RuleKind: String, CaseIterable, Codable, Sendable, Hashable {
    case hard
}

/// Who a rule protects.
///
/// "Not sure who" on the safety screen is stored as `.household`, which applies the rule to
/// every eater (G3; the safer reading).
public enum RuleScope: Codable, Sendable, Hashable {
    case household
    case member(MemberID)

    /// Whether this scope covers `memberID`.
    public func covers(_ memberID: MemberID) -> Bool {
        switch self {
        case .household:
            return true
        case .member(let id):
            return id == memberID
        }
    }
}

/// Where a rule came from. v1 rules are only ever entered by the user (AC-2.3, AC-12.4).
public enum RuleSource: String, CaseIterable, Codable, Sendable, Hashable {
    case user
}

/// A hard dietary restriction for a member or the whole household (plan section 3.1, V6).
///
/// `excludedTags` is a snapshot of the restriction's tags taken when the rule was created, so
/// a later catalog change never silently weakens a confirmed rule.
public struct Rule: Identifiable, Codable, Sendable, Hashable {
    public let id: RuleID
    public var kind: RuleKind
    public var scope: RuleScope
    public var restriction: RestrictionID
    public var excludedTags: Set<FoodTag>
    public var source: RuleSource
    public var createdAt: Date

    public init(
        id: RuleID,
        kind: RuleKind = .hard,
        scope: RuleScope,
        restriction: RestrictionID,
        excludedTags: Set<FoodTag>,
        source: RuleSource = .user,
        createdAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.scope = scope
        self.restriction = restriction
        self.excludedTags = excludedTags
        self.source = source
        self.createdAt = createdAt
    }

    /// A user-confirmed hard rule for `restriction`, snapshotting its excluded tags.
    public init(id: RuleID, scope: RuleScope, restriction: Restriction, createdAt: Date) {
        self.init(
            id: id, scope: scope, restriction: restriction.id, excludedTags: restriction.excludedTags,
            createdAt: createdAt)
    }
}
