import Foundation
import OMPDomain
import OMPServices

// The operation table. Every case calls the services (which run the safety gate and the independent
// validator themselves); nothing here plans, edits, clears a safety block or approves on its own.
// The ONLY approval path is `plan.approve` -> ApprovalBridge.swift.

private func enc<T: Encodable>(_ value: T) throws -> Data { try CanonicalJSON.encode(value) }

extension FacadeSession {
    func dispatch(_ request: Request, content: SeedContent) async throws -> Data {
        let engine = self.engine
        switch request.op {
        // MARK: meta and state
        case "meta.version":
            return try enc(MetaView(contentVersion: content.library.contentVersion))
        case "state.export":
            return try await exportState(engine)
        case "state.import":
            return try await importState(request, content: content)

        // MARK: household
        case "household.get":
            return try await householdView(engine)
        case "household.create":
            struct Args: Decodable { var adults: Int; var children: Int }
            let args = try request.decode(Args.self)
            // Bounded before the core adds the two counts (an overflow would trap).
            guard (0...Limits.maxMembersPerRole).contains(args.adults),
                (0...Limits.maxMembersPerRole).contains(args.children)
            else { throw FacadeError("household_size", "The household size is out of range.") }
            _ = try await engine.households.createHousehold(adults: args.adults, children: args.children)
            return try await householdView(engine)
        case "household.addMember":
            struct Args: Decodable { var role: MemberRole; var ageBand: AgeBand? }
            let args = try request.decode(Args.self)
            _ = try await engine.households.addMember(role: args.role, ageBand: args.ageBand)
            return try await householdView(engine)
        case "household.setName":
            struct Args: Decodable { var memberId: MemberID; var name: String? }
            let args = try request.decode(Args.self)
            try Limits.require((args.name?.count ?? 0) <= Limits.maxNameCharacters, "The name is too long.")
            _ = try await engine.households.setName(args.name, for: args.memberId)
            return try await householdView(engine)
        case "household.removeMember":
            // removeOwnRules: true is the onboarding "fewer people" path of the iOS app (rules tagged only
            // to the removed person go first). The core otherwise keeps them (soft delete, they cover nobody).
            struct Args: Decodable { var memberId: MemberID; var removeOwnRules: Bool? }
            let args = try request.decode(Args.self)
            // Remove the member FIRST: if that is refused (last member, unknown or deleted id) nothing has
            // changed. Only then drop the rules tagged to them (they cover nobody after a soft delete, so a
            // failure midway cannot weaken any other person's protection).
            let before = try await engine.households.household()
            let own = before?.rules.filter { $0.scope == .member(args.memberId) } ?? []
            _ = try await engine.households.removeMember(args.memberId)
            if args.removeOwnRules == true {
                for rule in own { _ = try await engine.safety.removeRule(rule.id) }
            }
            return try await householdView(engine)
        case "household.setAgeBand":
            struct Args: Decodable { var memberId: MemberID; var ageBand: AgeBand? }
            let args = try request.decode(Args.self)
            _ = try await engine.households.setAgeBand(args.ageBand, for: args.memberId)
            return try await householdView(engine)
        case "gate.status":
            return try enc(GateView(try await engine.households.gateStatus()))

        // MARK: safety
        case "safety.catalog":
            return try enc(CatalogView(restrictions: content.library.restrictions))
        case "safety.parse":
            struct Args: Decodable { var text: String }
            let args = try request.decode(Args.self)
            try Limits.require(args.text.count <= Limits.maxTextCharacters, "The text is too long.")
            return try enc(ParseView(candidates: content.parser.parse(args.text).map(CandidateView.init)))
        case "safety.confirm":
            struct Args: Decodable { var items: [SafetyItemArg] }
            let requests = try SafetyItemArg.ruleRequests(try request.decode(Args.self).items, requireItems: true)
            return try await safetyChange(engine, try await engine.safety.confirmSafetyAnswers(requests))
        case "safety.confirmNobody":
            // "No, nobody" is allowed only while the list of things to avoid is empty (C-026); the
            // household still refuses it when rules exist.
            struct Args: Decodable { var pendingItemCount: Int }
            let args = try request.decode(Args.self)
            guard args.pendingItemCount == 0 else {
                throw FacadeError("nobody_not_allowed", "\"No, nobody\" is not allowed while items to avoid are listed.")
            }
            return try await safetyChange(engine, try await engine.safety.confirmNobodyAvoidsAnything())
        case "safety.confirmMember":
            struct Args: Decodable { var memberId: MemberID; var items: [SafetyItemArg] }
            let args = try request.decode(Args.self)
            let requests = try SafetyItemArg.ruleRequests(
                args.items, requireItems: false, defaultScope: .member(args.memberId))
            return try await confirmMember(engine, args.memberId, requests)
        case "safety.addRule":
            struct Args: Decodable { var item: SafetyItemArg }
            let args = try request.decode(Args.self)
            let requests = try SafetyItemArg.ruleRequests([args.item], requireItems: true)
            return try await safetyChange(engine, try await engine.safety.addRule(requests[0]))
        case "safety.removeRule":
            // Removing a rule weakens safety: the UI must have asked the person first (AC-3.5).
            struct Args: Decodable { var ruleId: RuleID; var confirmed: Bool }
            let args = try request.decode(Args.self)
            guard args.confirmed else {
                throw FacadeError("confirmation_required", "Removing a safety rule needs the person's confirmation.")
            }
            return try await safetyChange(engine, try await engine.safety.removeRule(args.ruleId))
        case "safety.reconfirm":
            struct Args: Decodable { var memberIds: [MemberID]? }
            let args = try request.decode(Args.self)
            try Limits.require((args.memberIds?.count ?? 0) <= Limits.maxIDs, "Too many member ids.")
            return try await safetyChange(engine, try await engine.safety.reconfirm(args.memberIds))
        case "safety.recheck":
            var outcome = try await engine.safety.recheckOpenPlans()
            if let library = try await engine.safety.recheckIfLibraryChanged() { outcome = library }
            return try enc(RecheckView(outcome))

        // MARK: plan
        case "plan.current":
            return try await currentPlans(engine)
        case "plan.generate":
            struct Args: Decodable { var absences: [MealAbsence]? }
            let args = try request.decode(Args.self)
            try Limits.require((args.absences?.count ?? 0) <= Limits.maxAbsences, "Too many absences.")
            return try enc(PlanView(try await engine.plans.generateWeek(absences: Set(args.absences ?? []))))
        case "plan.get":
            struct Args: Decodable { var planId: MealPlanID }
            let args = try request.decode(Args.self)
            return try enc(PlanView(try await requirePlan(engine, args.planId)))
        case "plan.working":
            struct Args: Decodable { var seriesId: PlanSeriesID }
            let args = try request.decode(Args.self)
            return try enc(try await engine.plans.workingPlan(series: args.seriesId).map { PlanView($0) })
        case "plan.approved":
            struct Args: Decodable { var seriesId: PlanSeriesID }
            let args = try request.decode(Args.self)
            return try enc(try await engine.plans.activeApprovedPlan(series: args.seriesId).map { PlanView($0) })
        case "plan.pendingDiff":
            struct Args: Decodable { var seriesId: PlanSeriesID }
            let args = try request.decode(Args.self)
            return try enc(try await engine.plans.pendingDiff(series: args.seriesId).map(DiffView.init))
        case "plan.alternatives":
            struct Args: Decodable {
                var planId: MealPlanID
                var mealId: PlannedMealID
                var reason: RerollReason?
                var limit: Int?
            }
            let args = try request.decode(Args.self)
            let limit = min(max(args.limit ?? 3, 1), 12)
            let found = try await engine.plans.alternatives(
                for: args.mealId, in: args.planId, reason: args.reason, limit: limit)
            return try enc(AlternativesView(alternatives: found.map { AlternativeView(recipeId: $0.recipeId, reasons: $0.reasons) }))
        case "plan.swap":
            struct Args: Decodable { var planId: MealPlanID; var mealId: PlannedMealID; var recipeId: RecipeID }
            let args = try request.decode(Args.self)
            return try enc(PlanView(try await engine.plans.swap(args.mealId, in: args.planId, to: args.recipeId)))
        case "plan.reroll":
            struct Args: Decodable { var planId: MealPlanID; var mealId: PlannedMealID; var reason: RerollReason? }
            let args = try request.decode(Args.self)
            return try enc(PlanView(try await engine.plans.reroll(args.mealId, in: args.planId, reason: args.reason)))
        case "plan.regenerate":
            struct Args: Decodable { var planId: MealPlanID; var keepingLocked: Bool? }
            let args = try request.decode(Args.self)
            return try enc(
                PlanView(try await engine.plans.regenerate(args.planId, keepingLocked: args.keepingLocked ?? true)))
        case "plan.lock", "plan.unlock":
            struct Args: Decodable { var planId: MealPlanID; var mealId: PlannedMealID }
            let args = try request.decode(Args.self)
            return try enc(
                PlanView(
                    try await engine.plans.setLocked(request.op == "plan.lock", meal: args.mealId, in: args.planId)))
        case "plan.discard":
            struct Args: Decodable { var planId: MealPlanID }
            let args = try request.decode(Args.self)
            return try enc(PlanView(try await engine.plans.discard(args.planId)))

        // MARK: approval (the only door)
        case "plan.approvalPreview":
            struct Args: Decodable { var planId: MealPlanID }
            let args = try request.decode(Args.self)
            return try await approvalPreview(engine, args.planId)
        case "plan.approve":
            return try enc(try await ApprovalBridge.approve(request, plans: engine.plans, repositories: engine.repositories))

        default:
            throw FacadeError("unknown_op", "Unknown operation \"\(request.op)\".")
        }
    }

    // MARK: Helpers

    private func householdView(_ engine: Engine) async throws -> Data {
        let household = try await engine.households.household()
        return try enc(HouseholdView(household: household, gate: GateView(try await engine.households.gateStatus())))
    }

    private func safetyChange(_ engine: Engine, _ result: SafetyChangeResult) async throws -> Data {
        let gate = GateView(try await engine.households.gateStatus())
        return try enc(SafetyChangeView(household: result.household, gate: gate, recheck: RecheckView(result.recheck)))
    }

    /// The member variant of the safety question (S-02, F4): adds the member's rules that are not
    /// already in force, then confirms the answer (the same sequence as the iOS screen).
    private func confirmMember(_ engine: Engine, _ memberID: MemberID, _ requests: [RuleRequest]) async throws -> Data {
        let stored = try await engine.households.household()
        let existing = stored?.rules(covering: memberID).map(\.restriction) ?? []
        for request in requests where !existing.contains(request.restriction) {
            try await engine.safety.addRule(request)
        }
        let after = try await engine.households.household()
        let covered = !(after?.rules(covering: memberID).isEmpty ?? true)
        let result =
            covered
            ? try await engine.safety.confirmMemberAnswer(for: memberID)
            : try await engine.safety.confirmNothingToAvoid(for: memberID)
        return try await safetyChange(engine, result)
    }

    private func requirePlan(_ engine: Engine, _ id: MealPlanID) async throws -> MealPlan {
        guard let plan = try await engine.repositories.mealPlans.fetch(id: id) else {
            throw ServiceError.planNotFound(id)
        }
        return plan
    }

    private func currentPlans(_ engine: Engine) async throws -> Data {
        let gate = GateView(try await engine.households.gateStatus())
        guard let series = try await engine.plans.currentSeriesID() else {
            return try enc(CurrentPlansView(seriesId: nil, working: nil, approved: nil, pendingDiff: nil, gate: gate))
        }
        let working = try await engine.plans.workingPlan(series: series)
        let approved = try await engine.plans.activeApprovedPlan(series: series)
        let diff = try await engine.plans.pendingDiff(series: series)
        return try enc(
            CurrentPlansView(
                seriesId: series, working: working.map { PlanView($0) }, approved: approved.map { PlanView($0) },
                pendingDiff: diff.map(DiffView.init), gate: gate))
    }

    /// What the approval sheet shows. Records nothing: it cannot approve and changes no state.
    private func approvalPreview(_ engine: Engine, _ planID: MealPlanID) async throws -> Data {
        let plan = try await requirePlan(engine, planID)
        let household = try await engine.households.household()
        let refusal = household.flatMap { SafetyGate.approvalRefusal(for: $0) }
        var diff: DiffView?
        if let baseID = plan.basedOn, let base = try await engine.repositories.mealPlans.fetch(id: baseID) {
            diff = DiffView(PlanDiff(from: base, to: plan))
        }
        let blocked = plan.meals.contains { $0.blockedBySafety }
        let isDraft = plan.status == PlanStatus.draft
        return try enc(
            ApprovalPreviewView(
                plan: PlanView(plan), diff: diff, canApprove: isDraft && !blocked && refusal == nil && household != nil,
                gate: refusal.map { GateView(refusal: $0) }))
    }
}

struct MetaView: Encodable {
    var protocolVersion = 1
    var stateVersion = SnapshotFormat.version
    var coreVersion = OMPVersion.current
    var contentVersion: String
}

struct CatalogView: Encodable {
    var restrictions: [Restriction]
}

struct ParseView: Encodable {
    var candidates: [CandidateView]
}

struct AlternativesView: Encodable {
    var alternatives: [AlternativeView]
}

struct CurrentPlansView: Encodable {
    var seriesId: PlanSeriesID?
    var working: PlanView?
    var approved: PlanView?
    var pendingDiff: DiffView?
    var gate: GateView
}

struct ApprovalPreviewView: Encodable {
    var plan: PlanView
    var diff: DiffView?
    var canApprove: Bool
    var gate: GateView?
}

/// One thing to avoid, as the web safety screen holds it. Either a catalog restriction or text the
/// parser could not map (which must be resolved or removed before anything is saved, AC-2.4).
struct SafetyItemArg: Decodable {
    struct Scope: Decodable {
        /// "household" ("Not sure who", everyone, G3) or "member".
        var kind: String
        var memberId: MemberID?
    }

    var restriction: RestrictionID?
    var unresolvedText: String?
    var scope: Scope?

    func ruleScope(default fallback: RuleScope) throws -> RuleScope {
        guard let scope else { return fallback }
        switch scope.kind {
        case "household": return .household
        case "member":
            guard let id = scope.memberId else { throw FacadeError.invalid("scope.memberId is required for a member scope.") }
            return .member(id)
        default: throw FacadeError.invalid("scope.kind must be \"household\" or \"member\".")
        }
    }

    /// The requests for the services, without duplicates; refuses unresolved items.
    static func ruleRequests(
        _ items: [SafetyItemArg], requireItems: Bool, defaultScope: RuleScope = .household
    ) throws -> [RuleRequest] {
        try Limits.require(items.count <= Limits.maxItems, "Too many items.")
        for item in items {
            try Limits.require((item.unresolvedText?.count ?? 0) <= 2_000, "An item text is too long.")
        }
        if requireItems && items.isEmpty {
            throw FacadeError("no_items", "Add at least one restriction, or choose that nobody avoids anything.")
        }
        var unresolved: [JSONValue] = []
        var seen = Set<RuleRequest>()
        var requests: [RuleRequest] = []
        for item in items {
            if let text = item.unresolvedText {
                guard item.restriction == nil else {
                    throw FacadeError.invalid("An item is either a restriction or unresolvedText, not both.")
                }
                unresolved.append(.string(text))
                continue
            }
            guard let restriction = item.restriction else {
                throw FacadeError.invalid("Each item needs a restriction or unresolvedText.")
            }
            let request = RuleRequest(restriction: restriction, scope: try item.ruleScope(default: defaultScope))
            if seen.insert(request).inserted { requests.append(request) }
        }
        if !unresolved.isEmpty {
            throw FacadeError(
                "unresolved_items", "Pick the closest restriction for each unmapped item, or remove it.",
                details: .object(["texts": .array(unresolved)]))
        }
        return requests
    }
}
