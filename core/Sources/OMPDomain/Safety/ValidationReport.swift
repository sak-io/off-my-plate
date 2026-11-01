/// What a single violation is (ADR 0007).
public enum ViolationKind: Codable, Sendable, Hashable {
    /// The recipe contains (or may contain) `tag` via `ingredient`, and a rule covering the
    /// member excludes it (AC-4.1).
    case excludedTag(FoodTag, ingredient: IngredientID)
    /// The recipe uses an unverified ingredient and the member has a hard rule (AC-4.3).
    case unverifiedIngredient(IngredientID)
    /// The meal's recipe is not in the library: the validator fails closed.
    case unknownRecipe(RecipeID)
    /// A recipe line references an ingredient missing from the taxonomy: fails closed.
    case unknownIngredient(IngredientID)
}

/// One hard-rule violation: a meal, an eater, and why.
public struct Violation: Codable, Sendable, Hashable {
    public var mealId: PlannedMealID
    public var memberId: MemberID
    public var kind: ViolationKind

    public init(mealId: PlannedMealID, memberId: MemberID, kind: ViolationKind) {
        self.mealId = mealId
        self.memberId = memberId
        self.kind = kind
    }
}

/// The independent validator's verdict on one plan content (ADR 0007, plan section 12a #4).
///
/// Produced only by `OMPSafetyCheck.PlanValidator` (task T09). The initialiser is `package`
/// access: code inside the Core package (the validator and tests) can build a report, but the
/// Apple package and the app cannot. Approval also requires the report's `contentHash` to
/// match the draft's hash (ADR 0008).
///
/// Deliberately `Encodable` but **not** `Decodable` (the one exception to "all domain types are
/// Codable"): a synthesized `init(from:)` would be public, so any module could forge a passing
/// report by decoding JSON. A stored report is never trusted; approval always re-validates.
public struct ValidationReport: Encodable, Sendable, Hashable {
    public let planId: MealPlanID
    /// Hash of the plan content that was validated.
    public let contentHash: String
    /// Every violation found, in a deterministic order chosen by the validator.
    public let violations: [Violation]

    package init(planId: MealPlanID, contentHash: String, violations: [Violation]) {
        self.planId = planId
        self.contentHash = contentHash
        self.violations = violations
    }

    /// "Passed for everyone": no violations.
    public var passedForEveryone: Bool {
        violations.isEmpty
    }

    /// The failing meals, each once, in first-seen order.
    public var violatingMealIDs: [PlannedMealID] {
        var seen = Set<PlannedMealID>()
        var result: [PlannedMealID] = []
        for violation in violations where seen.insert(violation.mealId).inserted {
            result.append(violation.mealId)
        }
        return result
    }
}
