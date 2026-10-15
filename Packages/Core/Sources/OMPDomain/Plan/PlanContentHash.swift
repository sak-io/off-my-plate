import Foundation

/// The canonical encoding of a plan's content and its SHA-256 hash (ADR 0008, AC-5.2, AC-5.5).
///
/// The encoding is compact JSON with keys in sorted order, built by hand rather than with
/// `JSONEncoder` so that it is byte-identical on every platform:
///
/// ```
/// {"meals":[{"date":"2026-10-12","locked":false,"recipeId":"dal-tadka",
///   "servings":[{"memberId":"m1","notEating":false,"portion":1.0}],"slot":"dinner"}],
///  "weekStart":"2026-10-12"}
/// ```
///
/// - Included: week start; per meal its date, slot, recipe id (`null` when empty), locked and
///   servings (member id, portion, notEating).
/// - Excluded: meal ids, cooked state, explanations, empty reason and `blockedBySafety`, so
///   cooking a meal or an R1 safety re-check never voids an approval. Plan metadata (status,
///   revision, approval, dates) is not content either.
/// - Order-independent: servings are sorted by member id, then by their encoding; meals are
///   sorted by the UTF-8 bytes of their encoding (which starts with the date).
/// - Portions use Swift's shortest round-trip `Double` description (standard library, not
///   locale-dependent); `-0.0` is written as `0.0`.
///
/// The encoding is part of the persistence contract: changing it needs a re-hash migration.
extension MealPlan {
    /// The canonical encoding of this plan's content.
    public var canonicalContent: String {
        let encodedMeals = meals.map(PlanCanonicalEncoding.encode(meal:)).sorted(by: PlanCanonicalEncoding.utf8Precedes)
        return "{\"meals\":[" + encodedMeals.joined(separator: ",") + "],\"weekStart\":"
            + PlanCanonicalEncoding.string(weekStart.isoString) + "}"
    }

    /// Lowercase hex SHA-256 of `canonicalContent`.
    public var contentHash: String {
        SHA256.hexDigest(of: canonicalContent)
    }

    /// AC-5.5: the plan is `approved` **and** its current content still matches the hash stored
    /// at approval. Anything else is treated as not approved.
    public var isEffectivelyApproved: Bool {
        guard status == .approved, let approval else { return false }
        return approval.contentHash == contentHash
    }

    /// The meals downstream features may use (shopping list, Mark cooked): every meal not
    /// `blockedBySafety` (R1) if the plan is effectively approved, otherwise none.
    public var usableApprovedMeals: [PlannedMeal] {
        guard isEffectivelyApproved else { return [] }
        return meals.filter { !$0.blockedBySafety }
    }
}

/// Building blocks of the canonical encoding.
enum PlanCanonicalEncoding {
    static func encode(meal: PlannedMeal) -> String {
        let servings = meal.servings
            .map { (memberId: $0.memberId.rawValue, encoded: encode(serving: $0)) }
            .sorted { lhs, rhs in
                if lhs.memberId != rhs.memberId { return utf8Precedes(lhs.memberId, rhs.memberId) }
                return utf8Precedes(lhs.encoded, rhs.encoded)
            }
            .map(\.encoded)
        let recipe = meal.recipeId.map { string($0.rawValue) } ?? "null"
        return "{\"date\":" + string(meal.date.isoString)
            + ",\"locked\":" + (meal.locked ? "true" : "false")
            + ",\"recipeId\":" + recipe
            + ",\"servings\":[" + servings.joined(separator: ",") + "]"
            + ",\"slot\":" + string(meal.slot.rawValue) + "}"
    }

    static func encode(serving: MealServing) -> String {
        "{\"memberId\":" + string(serving.memberId.rawValue)
            + ",\"notEating\":" + (serving.notEating ? "true" : "false")
            + ",\"portion\":" + number(serving.portion) + "}"
    }

    /// Shortest round-trip description from the standard library; zero is normalised so that
    /// values that compare equal encode equally.
    static func number(_ value: Double) -> String {
        value == 0 ? "0.0" : value.description
    }

    /// A JSON string literal: quotes, backslashes and control characters are escaped; every
    /// other Unicode scalar is written as is (UTF-8 when hashed).
    static func string(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 {
                    let digits = Array("0123456789abcdef")
                    result += "\\u00" + String(digits[Int(scalar.value >> 4)]) + String(digits[Int(scalar.value & 0x0f)])
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }

    /// Byte-wise ordering, independent of locale and of Unicode normalisation.
    static func utf8Precedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }
}
