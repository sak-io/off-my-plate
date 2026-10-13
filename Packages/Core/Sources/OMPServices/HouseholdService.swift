import Foundation
import OMPDomain

/// What the root view shows (plan section 12a #1): onboarding, the app, or the safety cover.
public enum GateStatus: Sendable, Hashable {
    /// Onboarding has not created a household.
    case noHousehold
    /// Planning is allowed.
    case open
    /// Planning is refused; the refusal names who must answer (C-080, C-081).
    case refused(GateRefusal)
}

/// Onboarding and household membership (AC-1.2, AC-1.4, AC-3.2, AC-3.3, AC-3.4; task T18).
///
/// Member changes run the R1 re-check of open plans afterwards, so the plan state always
/// matches the household that is stored.
public final class HouseholdService: Sendable {
    let engine: PlanningEngine

    public init(context: ServiceContext) {
        self.engine = PlanningEngine(context: context)
    }

    var context: ServiceContext { engine.context }

    /// The stored household, if onboarding created one.
    public func household() async throws -> Household? {
        try await context.repositories.household.fetch()
    }

    /// The safety gate's verdict now (AC-3.1, G3). The root view shows the safety cover while
    /// it is `.refused`.
    public func gateStatus() async throws -> GateStatus {
        guard let household = try await context.repositories.household.fetch() else { return .noHousehold }
        switch SafetyGate.evaluate(household, clock: context.clock) {
        case .success: return .open
        case .failure(let refusal): return .refused(refusal)
        }
    }

    /// "Who's eating?" (AC-1.2, AC-1.3): creates the household with `adults` + `children`
    /// members, all `unasked`, so planning is blocked until the safety question is answered.
    ///
    /// - Throws: `.householdAlreadyExists`, `.householdSize`.
    @discardableResult
    public func createHousehold(adults: Int, children: Int) async throws -> Household {
        try await context.serialized {
            guard try await context.repositories.household.fetch() == nil else {
                throw ServiceError.householdAlreadyExists
            }
            let now = context.clock.now
            let household = try mappingDomainErrors {
                try Household.onboarding(
                    id: HouseholdID(context.makeID()), adults: adults, children: children, now: now,
                    makeMemberID: { MemberID(context.makeID()) })
            }
            try await context.repositories.household.replace(with: household)
            return household
        }
    }

    /// "What do you usually cook?" (AC-1.4): each picked cuisine is stored as a `stated`, active
    /// soft Fact for the household. Skipping (an empty list) stores nothing. Picking a cuisine
    /// that already has a fact restates it.
    ///
    /// - Returns: the facts that were saved.
    @discardableResult
    public func recordCuisines(_ cuisines: [CuisineID]) async throws -> [Fact] {
        try await context.serialized {
            guard try await context.repositories.household.fetch() != nil else { throw ServiceError.noHousehold }
            let now = context.clock.now
            var seen = Set<CuisineID>()
            var saved: [Fact] = []
            for cuisine in cuisines where seen.insert(cuisine).inserted {
                let key = FactKey(subject: .household, statement: .cuisineAffinity(cuisine))
                let id = FactLearner.stableID(for: key)
                let existing = try await context.repositories.facts.fetch(id: id)
                let fact = Fact(
                    id: id, subject: key.subject, statement: key.statement, origin: .stated, confidence: 1,
                    status: .active, suppressed: existing?.suppressed ?? false, createdAt: existing?.createdAt ?? now,
                    updatedAt: now)
                try await context.repositories.facts.save(fact)
                saved.append(fact)
            }
            return saved
        }
    }

    /// Adds a person (AC-3.2). The new member is `unasked`: the safety question is shown for
    /// them and planning stays blocked until it is answered. The approved plan stays usable
    /// (AC-3.3).
    @discardableResult
    public func addMember(role: MemberRole, ageBand: AgeBand?) async throws -> Member {
        try await context.serialized {
            var household = try await engine.requireHousehold()
            let now = context.clock.now
            let member = household.addMember(role: role, ageBand: ageBand, at: now, id: MemberID(context.makeID()))
            try await context.repositories.household.replace(with: household)
            _ = try await engine.recheckOpenPlans(household: household, now: now)
            return member
        }
    }

    /// Removes a person (soft delete, UX U3). A household keeps at least one member.
    @discardableResult
    public func removeMember(_ memberID: MemberID) async throws -> Household {
        try await context.serialized {
            var household = try await engine.requireHousehold()
            let now = context.clock.now
            try mappingDomainErrors { try household.removeMember(memberID, at: now) }
            try await context.repositories.household.replace(with: household)
            _ = try await engine.recheckOpenPlans(household: household, now: now)
            return household
        }
    }

    /// Changes a member's age band (AC-3.4). Crossing between child and grown bands resets the
    /// member to `unasked`, so the safety question is asked again.
    ///
    /// - Returns: whether the member was reset to `unasked`.
    @discardableResult
    public func setAgeBand(_ ageBand: AgeBand?, for memberID: MemberID) async throws -> Bool {
        try await context.serialized {
            var household = try await engine.requireHousehold()
            let now = context.clock.now
            let reset = try mappingDomainErrors { try household.setAgeBand(ageBand, for: memberID, at: now) }
            try await context.repositories.household.replace(with: household)
            _ = try await engine.recheckOpenPlans(household: household, now: now)
            return reset
        }
    }
}
