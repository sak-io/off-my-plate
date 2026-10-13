import Foundation
import OMPDomain

/// The persisted format of a plan's meals: `MealPlanRecord.content` (ADR 0003, TR-4).
///
/// OMPData owns this format; it deliberately does not reuse the domain types' synthesized
/// `Codable`, so a refactor in OMPDomain cannot silently change what is on disk. The golden
/// tests in `PlanContentDTOTests` pin version 1 byte-for-byte (structurally).
///
/// Version 1 (JSON, keys sorted):
/// ```
/// { "version": 1,
///   "meals": [ { "id", "date" ("yyyy-MM-dd"), "slot", "recipeId"?, "emptyReason"?, "locked",
///                "servings": [ { "memberId", "portion", "notEating" } ],
///                "reasons": [ { "kind", "ingredientId"?, "slot"?, "cuisineId"? } ],
///                "cooked"?: { "cookLogId", "cookedAt" (seconds since 2001-01-01T00:00:00Z) },
///                "blockedBySafety" } ] }
/// ```
/// Optional keys are omitted when nil. Enum values are their domain raw values / case names.
/// A new format adds a version and a decoding branch in `decodeMeals`; existing versions are
/// never edited.
public struct PlanContentDTO: Codable, Sendable, Hashable {
    /// The version this build writes.
    public static let currentVersion = 1

    public var version: Int
    public var meals: [Meal]

    public struct Meal: Codable, Sendable, Hashable {
        public var id: String
        public var date: String
        public var slot: String
        public var recipeId: String?
        public var emptyReason: String?
        public var locked: Bool
        public var servings: [Serving]
        public var reasons: [Reason]
        public var cooked: Cooked?
        public var blockedBySafety: Bool
    }

    public struct Serving: Codable, Sendable, Hashable {
        public var memberId: String
        public var portion: Double
        public var notEating: Bool
    }

    /// Optional members default to nil in the memberwise initialiser.
    public struct Reason: Codable, Sendable, Hashable {
        public var kind: String
        public var ingredientId: String?
        public var slot: String?
        public var cuisineId: String?
    }

    public struct Cooked: Codable, Sendable, Hashable {
        public var cookLogId: String
        /// `Date.timeIntervalSinceReferenceDate`: exact, unlike ISO 8601 with milliseconds.
        public var cookedAt: Double
    }

    private struct VersionHeader: Decodable {
        var version: Int
    }

    private static let entity = "PlannedMeal"

    // MARK: Domain -> DTO -> JSON

    /// The current-version DTO for `meals`. Throws for an empty id.
    public init(meals: [PlannedMeal]) throws {
        self.version = PlanContentDTO.currentVersion
        self.meals = try meals.map(PlanContentDTO.dto(for:))
    }

    /// `meals` as current-version JSON (sorted keys, deterministic).
    public static func encode(_ meals: [PlannedMeal]) throws -> Data {
        try Mapping.jsonEncoder().encode(PlanContentDTO(meals: meals))
    }

    // MARK: JSON -> DTO -> Domain

    /// The meals stored in `data`, whatever supported version wrote them.
    ///
    /// - Throws: `unreadablePlanContent` when there is no version, `unsupportedPlanContentVersion`
    ///   for a version newer than this build, and `PersistenceError` / `DecodingError` for bad
    ///   content.
    public static func decodeMeals(from data: Data, planId: String = "") throws -> [PlannedMeal] {
        let decoder = JSONDecoder()
        let header: VersionHeader
        do {
            header = try decoder.decode(VersionHeader.self, from: data)
        } catch {
            throw PersistenceError.unreadablePlanContent(planId: planId)
        }
        switch header.version {
        case 1:
            return try decoder.decode(PlanContentDTO.self, from: data).domainMeals()
        default:
            throw PersistenceError.unsupportedPlanContentVersion(header.version)
        }
    }

    /// The domain meals of a version-1 DTO.
    public func domainMeals() throws -> [PlannedMeal] {
        try meals.map(PlanContentDTO.domain(for:))
    }

    // MARK: Per-meal mapping

    private static func dto(for meal: PlannedMeal) throws -> Meal {
        Meal(
            id: try Mapping.raw(meal.id, entity: entity),
            date: meal.date.isoString,
            slot: meal.slot.rawValue,
            recipeId: try meal.recipeId.map { try Mapping.raw($0, entity: entity) },
            emptyReason: meal.emptyReason?.rawValue,
            locked: meal.locked,
            servings: try meal.servings.map {
                Serving(memberId: try Mapping.raw($0.memberId, entity: entity), portion: $0.portion, notEating: $0.notEating)
            },
            reasons: try meal.reasons.map(reason(for:)),
            cooked: try meal.cooked.map {
                Cooked(
                    cookLogId: try Mapping.raw($0.cookLogId, entity: entity),
                    cookedAt: $0.cookedAt.timeIntervalSinceReferenceDate)
            },
            blockedBySafety: meal.blockedBySafety
        )
    }

    private static func domain(for meal: Meal) throws -> PlannedMeal {
        PlannedMeal(
            id: try Mapping.entityID(meal.id, entity: entity),
            date: try Mapping.localDate(meal.date, entity: entity, field: "date"),
            slot: try Mapping.value(MealSlot.self, meal.slot, entity: entity, field: "slot"),
            recipeId: try Mapping.optionalEntityID(meal.recipeId, entity: entity),
            emptyReason: try Mapping.optionalValue(
                EmptyMealReason.self, meal.emptyReason, entity: entity, field: "emptyReason"),
            locked: meal.locked,
            servings: try meal.servings.map {
                MealServing(
                    memberId: try Mapping.entityID($0.memberId, entity: entity), portion: $0.portion,
                    notEating: $0.notEating)
            },
            reasons: try meal.reasons.map(reason(from:)),
            cooked: try meal.cooked.map {
                CookRef(
                    cookLogId: try Mapping.entityID($0.cookLogId, entity: entity),
                    cookedAt: Date(timeIntervalSinceReferenceDate: $0.cookedAt))
            },
            blockedBySafety: meal.blockedBySafety
        )
    }

    private static func reason(for reason: ExplanationReason) throws -> Reason {
        switch reason {
        case .usesYourIngredient(let id):
            return Reason(kind: "usesYourIngredient", ingredientId: try Mapping.raw(id, entity: entity))
        case .usesExpiringIngredient(let id):
            return Reason(kind: "usesExpiringIngredient", ingredientId: try Mapping.raw(id, entity: entity))
        case .quickWeekday(let slot):
            return Reason(kind: "quickWeekday", slot: slot.rawValue)
        case .goodForLunchboxes:
            return Reason(kind: "goodForLunchboxes")
        case .differentFromYesterday:
            return Reason(kind: "differentFromYesterday")
        case .cookedOften:
            return Reason(kind: "cookedOften")
        case .cuisineYouLike(let id):
            return Reason(kind: "cuisineYouLike", cuisineId: try Mapping.raw(id, entity: entity))
        case .repeatedFewSafeOptions:
            return Reason(kind: "repeatedFewSafeOptions")
        }
    }

    private static func reason(from reason: Reason) throws -> ExplanationReason {
        switch reason.kind {
        case "usesYourIngredient":
            return .usesYourIngredient(try Mapping.entityID(reason.ingredientId ?? "", entity: entity))
        case "usesExpiringIngredient":
            return .usesExpiringIngredient(try Mapping.entityID(reason.ingredientId ?? "", entity: entity))
        case "quickWeekday":
            return .quickWeekday(try Mapping.value(MealSlot.self, reason.slot ?? "", entity: entity, field: "reason.slot"))
        case "goodForLunchboxes":
            return .goodForLunchboxes
        case "differentFromYesterday":
            return .differentFromYesterday
        case "cookedOften":
            return .cookedOften
        case "cuisineYouLike":
            return .cuisineYouLike(try Mapping.entityID(reason.cuisineId ?? "", entity: entity))
        case "repeatedFewSafeOptions":
            return .repeatedFewSafeOptions
        default:
            throw PersistenceError.invalidValue(entity: entity, field: "reason.kind", value: reason.kind)
        }
    }
}

/// The persisted format of `CookLog.deductions`: `CookLogRecord.deductions` (TR-4).
///
/// Version 1: `{ "version": 1, "deductions": [ { "pantryItemId", "quantity", "unit" } ] }`,
/// keys sorted; `unit` is the `MeasureUnit` raw value (`"g"`, `"tbsp"`, ...).
public struct PantryDeductionsDTO: Codable, Sendable, Hashable {
    public static let currentVersion = 1

    public var version: Int
    public var deductions: [Deduction]

    public struct Deduction: Codable, Sendable, Hashable {
        public var pantryItemId: String
        public var quantity: Double
        public var unit: String
    }

    private struct VersionHeader: Decodable {
        var version: Int
    }

    private static let entity = "PantryDeduction"

    public static func encode(_ deductions: [PantryDeduction]) throws -> Data {
        let dto = PantryDeductionsDTO(
            version: currentVersion,
            deductions: try deductions.map {
                Deduction(
                    pantryItemId: try Mapping.raw($0.pantryItemId, entity: entity), quantity: $0.quantity,
                    unit: $0.unit.rawValue)
            })
        return try Mapping.jsonEncoder().encode(dto)
    }

    public static func decode(from data: Data, cookLogId: String = "") throws -> [PantryDeduction] {
        let decoder = JSONDecoder()
        let header: VersionHeader
        do {
            header = try decoder.decode(VersionHeader.self, from: data)
        } catch {
            throw PersistenceError.unreadableDeductions(cookLogId: cookLogId)
        }
        guard header.version == 1 else {
            throw PersistenceError.unsupportedDeductionsVersion(header.version)
        }
        return try decoder.decode(PantryDeductionsDTO.self, from: data).deductions.map {
            PantryDeduction(
                pantryItemId: try Mapping.entityID($0.pantryItemId, entity: entity), quantity: $0.quantity,
                unit: try Mapping.value(MeasureUnit.self, $0.unit, entity: entity, field: "unit"))
        }
    }
}
