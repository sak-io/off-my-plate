import Foundation
import OMPDomain

/// One confirmed item from the safety summary: a catalog restriction and who it protects
/// ("Not sure who" is `.household`, G3).
public struct RuleRequest: Sendable, Hashable {
    public var restriction: RestrictionID
    public var scope: RuleScope

    public init(restriction: RestrictionID, scope: RuleScope) {
        self.restriction = restriction
        self.scope = scope
    }
}

/// The household after a safety change, and what the R1 re-check did to open plans.
public struct SafetyChangeResult: Sendable, Hashable {
    public let household: Household
    public let recheck: SafetyRecheckOutcome

    public init(household: Household, recheck: SafetyRecheckOutcome) {
        self.household = household
        self.recheck = recheck
    }
}

/// Safety answers and hard-rule edits (AC-2.x, AC-3.2, AC-3.5, G3, R1; task T18).
///
/// Every change is saved and then, under the same lock, the open draft **and** the active
/// approved plan are re-validated against the new rules (R1, plan V1): unsafe approved meals
/// are flagged `blockedBySafety` (off the shopping list and out of Mark cooked) and a fixed
/// draft revision is proposed; an open draft has its unsafe meals re-planned.
///
/// Rules are built only from catalog restrictions (`PlanningLibrary.restrictions`), snapshotting
/// their excluded tags; a caller cannot supply its own tag set.
public final class SafetyService: Sendable {
    let engine: PlanningEngine

    public init(context: ServiceContext) {
        self.engine = PlanningEngine(context: context)
    }

    var context: ServiceContext { engine.context }

    /// "No, nobody" (AC-2.2): every member becomes `confirmedNone`.
    @discardableResult
    public func confirmNobodyAvoidsAnything() async throws -> SafetyChangeResult {
        try await change { household, now in
            try household.confirmNobodyAvoidsAnything(at: now)
        }
    }

    /// The safety summary's "Yes, save this" (AC-2.3): saves the confirmed rules; covered
    /// members become `stated`, everyone else `confirmedNone`.
    ///
    /// - Throws: `.unknownRestriction`, `.safetyTransition(...)`.
    @discardableResult
    public func confirmSafetyAnswers(_ requests: [RuleRequest]) async throws -> SafetyChangeResult {
        try await change { household, now in
            let rules = try requests.map { try makeRule($0, now: now) }
            try household.confirmSafetyAnswers(rules: rules, at: now)
        }
    }

    /// The re-ask for one member (an added member, AC-3.2, or after an age-band reset, AC-3.4):
    /// the user confirmed the rules that already cover them are complete.
    @discardableResult
    public func confirmMemberAnswer(for memberID: MemberID) async throws -> SafetyChangeResult {
        try await change { household, now in
            try household.confirmMemberAnswer(for: memberID, at: now)
        }
    }

    /// "Nothing to avoid" for one member.
    @discardableResult
    public func confirmNothingToAvoid(for memberID: MemberID) async throws -> SafetyChangeResult {
        try await change { household, now in
            try household.confirmNothingToAvoid(for: memberID, at: now)
        }
    }

    /// Adds a hard rule from Settings (AC-3.5) and runs the R1 re-check.
    @discardableResult
    public func addRule(_ request: RuleRequest) async throws -> SafetyChangeResult {
        try await change { household, now in
            try household.addRule(try makeRule(request, now: now), at: now)
        }
    }

    /// Removes a hard rule after the user confirmed it (AC-3.5) and runs the re-check.
    @discardableResult
    public func removeRule(_ ruleID: RuleID) async throws -> SafetyChangeResult {
        try await change { household, now in
            try household.removeRule(ruleID, confirmedAt: now)
        }
    }

    /// The one-tap "Still correct?" (G3) for `memberIDs` (`nil`: everyone answered).
    @discardableResult
    public func reconfirm(_ memberIDs: [MemberID]? = nil) async throws -> SafetyChangeResult {
        try await change { household, now in
            _ = try household.reconfirmSafety(for: memberIDs, at: now)
        }
    }

    /// Runs the R1 re-check of every open draft and active approved plan now, against the
    /// stored household and the current library. Idempotent. The composition root calls it at
    /// launch, which also repairs a re-check interrupted by a failed save.
    @discardableResult
    public func recheckOpenPlans() async throws -> SafetyRecheckOutcome {
        try await context.serialized {
            guard let household = try await context.repositories.household.fetch() else {
                return SafetyRecheckOutcome()
            }
            return try await engine.recheckOpenPlans(household: household, now: context.clock.now)
        }
    }

    /// The seed-update trigger (ADR 0010, T13 review-1): when any open plan was last checked
    /// against another `contentVersion` than the current library's (a recipe or ingredient tag
    /// may have changed), runs the R1 re-check, which stamps the new version.
    ///
    /// - Returns: the outcome, or `nil` when every open plan is already on this version.
    @discardableResult
    public func recheckIfLibraryChanged() async throws -> SafetyRecheckOutcome? {
        try await context.serialized {
            guard let household = try await context.repositories.household.fetch() else { return nil }
            let version = context.library.contentVersion
            let plans = try await context.repositories.mealPlans.fetchAll()
            let stale = plans.contains { plan in
                (plan.status == .draft || plan.status == .approved) && plan.contentVersion != version
            }
            guard stale else { return nil }
            return try await engine.recheckOpenPlans(household: household, now: context.clock.now)
        }
    }

    // MARK: Private

    private func makeRule(_ request: RuleRequest, now: Date) throws -> Rule {
        guard let restriction = context.library.restriction(request.restriction) else {
            throw ServiceError.unknownRestriction(request.restriction)
        }
        return Rule(id: RuleID(context.makeID()), scope: request.scope, restriction: restriction, createdAt: now)
    }

    /// Applies `mutation` to the stored household, saves it, then re-checks open plans. A
    /// throwing mutation saves nothing.
    private func change(
        _ mutation: (inout Household, Date) throws -> Void
    ) async throws -> SafetyChangeResult {
        try await context.serialized {
            var household = try await engine.requireHousehold()
            let now = context.clock.now
            try mappingDomainErrors { try mutation(&household, now) }
            try await context.repositories.household.replace(with: household)
            let recheck = try await engine.recheckOpenPlans(household: household, now: now)
            return SafetyChangeResult(household: household, recheck: recheck)
        }
    }
}
