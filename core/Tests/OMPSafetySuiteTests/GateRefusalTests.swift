import Foundation
import OMPDomain
import OMPRecipes
import Testing

/// The safety gate guards every planner entry point (T12; AC-3.1, G3; ADR 0007 check (a)).
///
/// A `SafetyClearance` can only come from `SafetyGate` (compile-time: its initialiser is
/// file-private; `scripts/lint-safety.sh` keeps it that way), and every entry point takes one.
/// So "the planner refuses an unasked or overdue household" means both:
/// 1. the gate issues no clearance for such a household, and
/// 2. a clearance issued before the household became unasked or overdue is refused by every
///    entry point with `PlannerError.clearanceNotValid`.
@Suite("Safety suite: gate refusal for every planner entry point")
struct GateRefusalTests {
    typealias F = SuiteFixture

    /// Every public planner entry point (`scripts/lint-safety.sh` fails if a public planner
    /// function without a `SafetyClearance` parameter is added).
    enum EntryPoint: String, CaseIterable, Sendable {
        case generateWeek
        case alternatives
        case reroll
        case regenerate
    }

    /// How a cleared household stops being plannable.
    enum Condition: String, CaseIterable, Sendable {
        /// A new member was added and has not been asked about allergies (AC-3.1, AC-3.2).
        case newUnaskedMember
        /// An existing member's answer was withdrawn (back to `unasked`).
        case memberResetToUnasked
        /// An answer was confirmed but its date is missing (fails closed, TR-3).
        case confirmedWithoutDate
        /// 181 days have passed since the answers were confirmed (G3).
        case overdue
        /// One member's answer is overdue while the other's is fresh (G3).
        case oneMemberOverdue
    }

    /// The household and instant after `condition` applies to the cleared `F.pair`.
    static func apply(_ condition: Condition, to household: Household) -> (household: Household, now: Date) {
        var changed = household
        switch condition {
        case .newUnaskedMember:
            changed.members.append(
                Member(id: "m-new", label: MemberLabel(role: .adult, number: 2), ageBand: .adult))
            return (changed, F.now)
        case .memberResetToUnasked:
            changed.members[0].safetyStatus = .unasked
            changed.members[0].safetyConfirmedAt = nil
            return (changed, F.now)
        case .confirmedWithoutDate:
            changed.members[1].safetyConfirmedAt = nil
            return (changed, F.now)
        case .overdue:
            return (changed, F.now + 181 * F.day)
        case .oneMemberOverdue:
            // Re-confirm the adult 100 days from now; the child's answer stays at F.now.
            let later = F.now + 181 * F.day
            changed.members[0].safetyConfirmedAt = F.now + 100 * F.day
            return (changed, later)
        }
    }

    static let peanutRuleForChild = [
        Rule(id: "rule-a", scope: .member(F.child), restriction: "peanuts", excludedTags: [.peanut], createdAt: F.now)
    ]

    static func expectedRefusal(_ condition: Condition) -> GateRefusal {
        switch condition {
        case .newUnaskedMember: return .safetyUnanswered(["m-new"])
        case .memberResetToUnasked: return .safetyUnanswered([F.adult])
        case .confirmedWithoutDate: return .safetyUnanswered([F.child])
        case .overdue: return .reconfirmationDue([F.adult, F.child])
        case .oneMemberOverdue: return .reconfirmationDue([F.child])
        }
    }

    @Test("the gate issues no clearance for an unasked or overdue household", arguments: Condition.allCases)
    func gateRefuses(condition: Condition) throws {
        let rules = Self.peanutRuleForChild
        let (household, instant) = Self.apply(condition, to: F.pair(rules: rules))
        let result = SafetyGate.evaluate(household, now: instant, timeZone: F.utc)
        guard case .failure(let refusal) = result else {
            Issue.record("\(condition): the gate issued a clearance")
            return
        }
        #expect(refusal == Self.expectedRefusal(condition))
    }

    @Test("a freshly onboarded household (everyone unasked) gets no clearance")
    func onboardedHouseholdIsRefused() throws {
        var counter = 0
        let household = try Household.onboarding(id: "h-onboarded", adults: 2, children: 2, now: F.now) {
            counter += 1
            return MemberID("m\(counter)")
        }
        let result = SafetyGate.evaluate(household, now: F.now, timeZone: F.utc)
        guard case .failure(let refusal) = result else {
            Issue.record("the gate cleared an onboarded household")
            return
        }
        #expect(refusal == .safetyUnanswered(["m1", "m2", "m3", "m4"]))
    }

    @Test(
        "every planner entry point refuses a clearance once a member is unasked or overdue",
        arguments: EntryPoint.allCases, Condition.allCases)
    func entryPointRefuses(entryPoint: EntryPoint, condition: Condition) throws {
        let seed = try F.seed()
        let library = F.plannerLibrary(seed)
        let rules = Self.peanutRuleForChild
        let cleared = F.pair(rules: rules)
        let clearance = try F.clearance(cleared)
        // A plan made while the clearance was valid, with an editable meal to target.
        let plan = try WeekPlanner.generateWeek(
            clearance: clearance, household: cleared, library: library, request: F.request(seed: 7), now: F.now,
            timeZone: F.utc)
        let meal = try #require(plan.meals.first { $0.recipeId != nil && !$0.locked })

        // Sanity: with the original household and instant every entry point works.
        let baseline = Self.call(
            entryPoint, clearance: clearance, household: cleared, plan: plan, mealID: meal.id, library: library,
            now: F.now)
        #expect(baseline == nil, "\(entryPoint) failed with a valid clearance")

        let (changed, instant) = Self.apply(condition, to: cleared)
        let error = Self.call(
            entryPoint, clearance: clearance, household: changed, plan: plan, mealID: meal.id, library: library,
            now: instant)
        #expect(error == .clearanceNotValid, "\(entryPoint) under \(condition)")
    }

    /// Calls `entryPoint` and returns the planner error it threw, or `nil`.
    static func call(
        _ entryPoint: EntryPoint, clearance: SafetyClearance, household: Household, plan: MealPlan,
        mealID: PlannedMealID, library: PlannerLibrary, now: Date
    ) -> PlannerError? {
        F.plannerError {
            switch entryPoint {
            case .generateWeek:
                _ = try WeekPlanner.generateWeek(
                    clearance: clearance, household: household, library: library, request: F.request(seed: 8),
                    now: now, timeZone: F.utc)
            case .alternatives:
                _ = try WeekPlanner.alternatives(
                    for: mealID, in: plan, clearance: clearance, household: household, library: library, now: now,
                    timeZone: F.utc)
            case .reroll:
                _ = try WeekPlanner.reroll(
                    mealID, in: plan, reason: nil, clearance: clearance, household: household, library: library,
                    now: now, timeZone: F.utc)
            case .regenerate:
                _ = try WeekPlanner.regenerate(
                    plan, clearance: clearance, household: household, library: library, now: now, timeZone: F.utc)
            }
        }
    }
}
