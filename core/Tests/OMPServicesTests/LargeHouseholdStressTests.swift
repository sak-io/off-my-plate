import Foundation
import OMPDomain
import OMPRecipes
import OMPServices
import Testing

/// W02: a 12-member household (the maximum), two consecutive weeks (14 days, all slots), many edits and an
/// R1 recheck over the real seed. It runs in the Wasm DEBUG test set on purpose: debug frames are the largest,
/// so this is the deepest call stack the suite produces and exercises the linked stack size (docs/windows/w02-report.md).
@Suite("Large household stress (stack depth on Wasm)")
struct LargeHouseholdStressTests {
    @Test("12 members, 14 days, every slot: plan, edit every meal, approve, add a rule, re-plan; all validated")
    func twelveMembersTwoWeeks() async throws {
        let seed = try SeedLoader.load(SeedLoader.embeddedFiles())
        let env = ServicesEnv(
            library: PlanningLibrary(seed: seed),
            clock: TestClock(now: GoldenWeekPlanTests.now, timeZone: GoldenWeekPlanTests.zone), idPrefix: "stress")
        let created = try await env.households.createHousehold(adults: 6, children: 6)
        let ids = created.members.map(\.id)
        #expect(ids.count == 12)
        _ = try await env.safety.confirmSafetyAnswers([
            RuleRequest(restriction: "peanuts", scope: .member(ids[6])),
            RuleRequest(restriction: "sesame", scope: .member(ids[7])),
            RuleRequest(restriction: "egg", scope: .member(ids[2])),
            RuleRequest(restriction: "tree-nuts", scope: .member(ids[4])),
        ])

        var approvedMeals = 0
        for _ in 0..<2 {
            let draft = try await env.plans.generateWeek()
            #expect(draft.report.passedForEveryone)
            #expect(draft.plan.meals.count == 21)
            let series = draft.plan.seriesId
            var edits = 0
            for index in 0..<draft.plan.meals.count {
                let working = try #require(try await env.plans.workingPlan(series: series))
                let meal = working.meals[index]
                if let rerolled = try? await env.plans.reroll(meal.id, in: working.id, reason: nil) {
                    #expect(rerolled.report.passedForEveryone)
                    edits += 1
                }
            }
            #expect(edits > 0)
            let working = try #require(try await env.plans.workingPlan(series: series))
            let outcome = try await env.plans.approve(working.id, confirmation: UserConfirmation())
            approvedMeals += outcome.approved.meals.count
        }
        #expect(approvedMeals == 42)

        // R1: a household-wide rule after approval re-validates both approved weeks without crashing or hanging.
        let result = try await env.safety.addRule(RuleRequest(restriction: "fish", scope: .household))
        #expect(result.recheck.planningRefusal == nil)
        for proposed in result.recheck.proposedDrafts {
            let plan = try await env.storedPlan(proposed)
            #expect(plan.meals.allSatisfy { !$0.blockedBySafety })
        }
        print("STRESS-OK members=12 days=14 meals=\(approvedMeals) edits-per-week>0")
    }
}
