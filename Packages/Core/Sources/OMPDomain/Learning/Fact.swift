import Foundation

/// Who a fact is about (G10: household-level unless the user attributes it to a member).
public enum FactSubject: Codable, Sendable, Hashable {
    case household
    case member(MemberID)
}

/// What a fact says (ADR 0013). Soft preferences only: there is deliberately no case that
/// can express an allergy or a hard restriction, so learning can never create one (AC-12.4).
public enum FactStatement: Codable, Sendable, Hashable {
    case cuisineAffinity(CuisineID)
    case dislikesRecipe(RecipeID)
    case dislikesIngredient(IngredientID)
    case prefersQuickWeekday
    case staple(IngredientID)
    case favouriteRecipe(RecipeID)
}

/// How the app came to know a fact (tech section 5.2; AC-12.5 "said / confirmed / noticed /
/// default").
public enum FactOrigin: String, CaseIterable, Codable, Sendable, Hashable {
    /// The user said or picked it (for example cuisines in onboarding, AC-1.4).
    case stated
    /// Inferred, then confirmed by the user ("Yes" on a reflect-back card).
    case confirmed
    /// Observed from behaviour; a weak, decaying weight.
    case inferred
    /// An app assumption, replaced as soon as better information exists.
    case appDefault = "default"
}

/// Where a fact is in its life (AC-12.2, AC-12.3).
public enum FactStatus: String, CaseIterable, Codable, Sendable, Hashable {
    /// Inferred evidence below the proposal threshold; not shown.
    case observing
    /// Ready for a reflect-back card.
    case proposed
    /// Used by the planner's scores.
    case active
    /// "Not really" or "Don't ask again".
    case dismissed
    /// "Forget": evidence older than `forgottenAt` is ignored for this key.
    case forgotten
}

/// The identity of a fact: one statement about one subject. Suppression and forgetting work
/// per key.
public struct FactKey: Codable, Sendable, Hashable {
    public var subject: FactSubject
    public var statement: FactStatement

    public init(subject: FactSubject, statement: FactStatement) {
        self.subject = subject
        self.statement = statement
    }
}

/// A soft fact about the household (tech section 5.2, ADR 0013).
public struct Fact: Identifiable, Codable, Sendable, Hashable {
    public let id: FactID
    public var subject: FactSubject
    public var statement: FactStatement
    public var origin: FactOrigin
    /// 0...1. Meaningful for inferred facts; stated and confirmed facts use 1.
    public var confidence: Double
    public var status: FactStatus
    /// "Don't ask again": never re-proposed (AC-12.3).
    public var suppressed: Bool
    public var forgottenAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: FactID,
        subject: FactSubject = .household,
        statement: FactStatement,
        origin: FactOrigin,
        confidence: Double,
        status: FactStatus,
        suppressed: Bool = false,
        forgottenAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.subject = subject
        self.statement = statement
        self.origin = origin
        self.confidence = confidence
        self.status = status
        self.suppressed = suppressed
        self.forgottenAt = forgottenAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var key: FactKey {
        FactKey(subject: subject, statement: statement)
    }
}
