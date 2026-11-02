import Foundation
import OMPDomain
import OMPServices

// Response shapes. Domain types that are already Codable are encoded as they are (the storage
// contract, ADR 0003); the views add derived facts the web UI needs and must not recompute.

struct GateView: Encodable, Sendable {
    /// "noHousehold", "open" or "refused".
    var status: String
    /// For "refused": "safetyUnanswered" or "reconfirmationDue".
    var reason: String?
    var memberIds: [String]?

    init(_ status: GateStatus) {
        switch status {
        case .noHousehold:
            self.status = "noHousehold"
        case .open:
            self.status = "open"
        case .refused(let refusal):
            self.status = "refused"
            let details = FacadeError.gateDetails(refusal)
            self.reason = details["reason"]?.stringValue
            self.memberIds = refusal.memberIDs.map(\.rawValue)
        }
    }

    init(refusal: GateRefusal) {
        self.init(.refused(refusal))
    }
}

struct HouseholdView: Encodable, Sendable {
    var household: Household?
    var gate: GateView
}

struct PlanView: Encodable, Sendable {
    var plan: MealPlan
    /// Hex SHA-256 of the plan content (what the approval sheet shows and `plan.approve` must echo).
    var contentHash: String
    /// Approved and still the content that was approved (AC-5.5).
    var effectivelyApproved: Bool
    /// Meals an R1 re-check flagged (off the shopping list and out of Mark cooked until a fixed revision is approved).
    var blockedMealIds: [String]
    /// The independent validator's report for exactly this content, when the operation produced one.
    var report: ValidationReport?

    init(_ plan: MealPlan, report: ValidationReport? = nil) {
        self.plan = plan
        self.contentHash = plan.contentHash
        self.effectivelyApproved = plan.isEffectivelyApproved
        self.blockedMealIds = plan.meals.filter(\.blockedBySafety).map { $0.id.rawValue }
        self.report = report
    }

    init(_ validated: ValidatedPlan) {
        self.init(validated.plan, report: validated.report)
    }
}

struct DiffView: Encodable, Sendable {
    struct Change: Encodable, Sendable {
        var date: LocalDate
        var slot: MealSlot
        var kinds: [String]
        var listed: Bool
        var was: PlannedMeal?
        var now: PlannedMeal?
    }

    var changes: [Change]
    /// The "{n}" in "Approve {n} changes?".
    var listedCount: Int

    init(_ diff: PlanDiff) {
        changes = diff.changes.map {
            Change(
                date: $0.date, slot: $0.slot, kinds: $0.kinds.map(\.rawValue), listed: $0.isListed, was: $0.was,
                now: $0.now)
        }
        listedCount = diff.listedChanges.count
    }
}

struct RecheckView: Encodable, Sendable {
    var blockedMealIds: [String]
    var fixedDraftIds: [String]
    var proposedDraftIds: [String]
    var planningRefusal: GateView?
    var clean: Bool

    init(_ outcome: SafetyRecheckOutcome) {
        blockedMealIds = outcome.blockedMeals.map(\.rawValue)
        fixedDraftIds = outcome.fixedDrafts.map(\.rawValue)
        proposedDraftIds = outcome.proposedDrafts.map(\.rawValue)
        planningRefusal = outcome.planningRefusal.map { GateView(refusal: $0) }
        clean = outcome.isClean
    }
}

struct SafetyChangeView: Encodable, Sendable {
    var household: Household
    var gate: GateView
    var recheck: RecheckView
}

struct CandidateView: Encodable, Sendable {
    /// "restriction" or "unmapped".
    var kind: String
    var restriction: String?
    var matchedText: String?
    var text: String?
    var memberHint: String?

    init(_ candidate: SafetyCandidate) {
        switch candidate {
        case .restriction(let id, let matched, let hint):
            kind = "restriction"
            restriction = id.rawValue
            matchedText = matched
            memberHint = hint
        case .unmapped(let text, let hint):
            kind = "unmapped"
            self.text = text
            memberHint = hint
        }
    }
}

struct AlternativeView: Encodable, Sendable {
    var recipeId: RecipeID
    var reasons: [ExplanationReason]
}
