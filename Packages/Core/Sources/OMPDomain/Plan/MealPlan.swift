import Foundation

/// A slot in a day's plan (plan section 5 step 2).
public enum MealSlot: String, CaseIterable, Codable, Sendable, Hashable {
    case breakfast
    case lunch
    case dinner
    case snack
    /// Per school day for children with `needsSchoolLunch` (AC-7.2); filled only from
    /// `lunchboxSuitable` recipes.
    case lunchbox

    /// The recipe meal type that fits this slot, or `nil` for `.lunchbox` (which uses the
    /// recipe's `lunchboxSuitable` flag instead).
    public var mealType: MealType? {
        switch self {
        case .breakfast: return .breakfast
        case .lunch: return .lunch
        case .dinner: return .dinner
        case .snack: return .snack
        case .lunchbox: return nil
        }
    }
}

/// Plan lifecycle state (ADR 0008).
public enum PlanStatus: String, CaseIterable, Codable, Sendable, Hashable {
    case draft
    case approved
    case superseded
    case discarded
}

/// Who approved a plan. v1 has one device and no accounts (G8); the field exists so a rule
/// such as "adults only" can be added with sharing.
public enum Approver: String, CaseIterable, Codable, Sendable, Hashable {
    case thisDevice
}

/// The record of an explicit in-app approval (AC-5.2, ADR 0008).
public struct PlanApproval: Codable, Sendable, Hashable {
    public var approver: Approver
    public var approvedAt: Date
    /// Lowercase hex SHA-256 of the plan's canonical content (computed in T13). A plan whose
    /// current hash differs is not effectively approved (AC-5.5).
    public var contentHash: String

    public init(approver: Approver = .thisDevice, approvedAt: Date, contentHash: String) {
        self.approver = approver
        self.approvedAt = approvedAt
        self.contentHash = contentHash
    }
}

/// One member's share of a planned meal (AC-6.2, AC-6.3).
public struct MealServing: Codable, Sendable, Hashable {
    public var memberId: MemberID
    /// Portion relative to one adult portion (1.0).
    public var portion: Double
    /// A member who is not eating gets no serving and their rules do not constrain the slot.
    public var notEating: Bool

    public init(memberId: MemberID, portion: Double, notEating: Bool = false) {
        self.memberId = memberId
        self.portion = portion
        self.notEating = notEating
    }

    /// The default serving for `member`: their default portion (age band or override), eating.
    public init(defaultFor member: Member) {
        self.init(memberId: member.id, portion: member.defaultPortion)
    }
}

/// Why a planned meal has no recipe.
public enum EmptyMealReason: String, CaseIterable, Codable, Sendable, Hashable {
    /// Hard rules left no valid recipe (AC-4.4).
    case noSafeRecipe
    /// The independent validator rejected the planner's choice, so it was removed (a planner
    /// bug, logged as a programmer error; plan section 5).
    case removedByValidator
}

/// Link from a meal to its cook log once "Mark cooked" was confirmed (AC-9.6).
/// Not part of the content hash, so cooking never voids an approval (ADR 0008).
public struct CookRef: Codable, Sendable, Hashable {
    public var cookLogId: CookLogID
    public var cookedAt: Date

    public init(cookLogId: CookLogID, cookedAt: Date) {
        self.cookLogId = cookLogId
        self.cookedAt = cookedAt
    }
}

/// One slot on one day of a plan (plan section 3.1).
public struct PlannedMeal: Identifiable, Codable, Sendable, Hashable {
    public let id: PlannedMealID
    public var date: LocalDate
    public var slot: MealSlot
    /// `nil` when the meal is empty; then `emptyReason` says why.
    public var recipeId: RecipeID?
    public var emptyReason: EmptyMealReason?
    public var locked: Bool
    /// One entry per member considered for this meal, including those not eating.
    public var servings: [MealServing]
    /// Up to two template reasons for the choice (AC-4.7); rendered by the UI.
    public var reasons: [ExplanationReason]
    public var cooked: CookRef?
    /// Set when a hard-rule change made this approved meal unsafe (R1): it is excluded from
    /// the shopping list and Mark cooked until replaced.
    public var blockedBySafety: Bool

    public init(
        id: PlannedMealID,
        date: LocalDate,
        slot: MealSlot,
        recipeId: RecipeID?,
        emptyReason: EmptyMealReason? = nil,
        locked: Bool = false,
        servings: [MealServing],
        reasons: [ExplanationReason] = [],
        cooked: CookRef? = nil,
        blockedBySafety: Bool = false
    ) {
        self.id = id
        self.date = date
        self.slot = slot
        self.recipeId = recipeId
        self.emptyReason = emptyReason
        self.locked = locked
        self.servings = servings
        self.reasons = reasons
        self.cooked = cooked
        self.blockedBySafety = blockedBySafety
    }

    /// Whether the meal has no recipe.
    public var isEmpty: Bool {
        recipeId == nil
    }

    /// The members who eat this meal (AC-6.3), in serving order.
    public var eaterIDs: [MemberID] {
        servings.filter { !$0.notEating }.map(\.memberId)
    }
}

/// A plan revision: 7 days of meals from `weekStart` (plan section 3.1, R8, ADR 0008).
public struct MealPlan: Identifiable, Codable, Sendable, Hashable {
    /// Number of days a plan covers (R8).
    public static let lengthInDays = 7

    public let id: MealPlanID
    /// Shared by every revision of the same plan.
    public var seriesId: PlanSeriesID
    /// 1 for the first draft; editing an approved plan creates `revision + 1`.
    public var revision: Int
    /// The approved revision this draft was derived from, if any.
    public var basedOn: MealPlanID?
    /// First day of the plan (R8: today for the first plan, otherwise the day after the
    /// previous plan's last day). Not necessarily a Monday.
    public var weekStart: LocalDate
    public var status: PlanStatus
    public var meals: [PlannedMeal]
    public var approval: PlanApproval?
    /// Version of the seed library the plan was made from.
    public var contentVersion: String
    public var createdAt: Date

    public init(
        id: MealPlanID,
        seriesId: PlanSeriesID,
        revision: Int = 1,
        basedOn: MealPlanID? = nil,
        weekStart: LocalDate,
        status: PlanStatus = .draft,
        meals: [PlannedMeal],
        approval: PlanApproval? = nil,
        contentVersion: String,
        createdAt: Date
    ) {
        self.id = id
        self.seriesId = seriesId
        self.revision = revision
        self.basedOn = basedOn
        self.weekStart = weekStart
        self.status = status
        self.meals = meals
        self.approval = approval
        self.contentVersion = contentVersion
        self.createdAt = createdAt
    }

    /// The last day the plan covers (`weekStart + 6`).
    public var endDate: LocalDate {
        weekStart.adding(days: MealPlan.lengthInDays - 1)
    }

    /// The plan's days in order.
    public var dates: [LocalDate] {
        (0..<MealPlan.lengthInDays).map { weekStart.adding(days: $0) }
    }

    /// The meal with `id`.
    public func meal(_ id: PlannedMealID) -> PlannedMeal? {
        meals.first { $0.id == id }
    }
}
