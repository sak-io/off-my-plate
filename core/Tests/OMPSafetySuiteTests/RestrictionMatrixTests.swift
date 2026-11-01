import Foundation
import OMPDomain
import OMPRecipes
import OMPSafetyCheck
import Testing

/// Every catalog restriction and every pair of restrictions, against every seed recipe in every
/// slot (T12; AC-4.1, AC-4.3, AC-4.5, AC-6.3; ADR 0007).
@Suite("Safety suite: restriction × recipe × slot, and restriction pairs")
struct RestrictionMatrixTests {
    typealias F = SuiteFixture

    /// Where a rule applies, relative to the fixed adult + school-child pair.
    enum Scope: String, CaseIterable, Sendable {
        case child
        case adult
        case household

        var ruleScope: RuleScope {
            switch self {
            case .child: return .member(F.child)
            case .adult: return .member(F.adult)
            case .household: return .household
            }
        }
    }

    @Test(
        "every restriction × every seed recipe × every slot: filter, validator and oracle agree",
        arguments: Scope.allCases)
    func everyRestrictionRecipeSlot(scope: Scope) throws {
        let seed = try F.seed()
        let planner = F.plannerLibrary(seed)
        let checker = F.checkLibrary(seed)
        #expect(seed.catalog.restrictions.count >= 10, "the catalog lost restrictions")
        #expect(seed.recipes.count >= 20, "the seed library lost recipes")

        var total = F.Agreement()
        // The no-rule household first: everything that fits is safe.
        let noRules = F.pair(rules: [])
        total.merge(
            F.agreement(
                household: noRules, clearance: try F.clearance(noRules), cases: F.pairCases, seed: seed,
                planner: planner, checker: checker, label: "no rules"))
        for restriction in seed.catalog.restrictions {
            let rule = Rule(id: "rule-a", scope: scope.ruleScope, restriction: restriction, createdAt: F.now)
            let household = F.pair(rules: [rule])
            total.merge(
                F.agreement(
                    household: household, clearance: try F.clearance(household), cases: F.pairCases, seed: seed,
                    planner: planner, checker: checker, label: "\(restriction.id) on \(scope)"))
        }
        #expect(total.mismatches.isEmpty, "\(total.mismatches.count) disagreements: \(total.mismatches.prefix(20))")
        // Not vacuous: both verdicts occur.
        #expect(total.safe > 0)
        #expect(total.unsafe > 0)
    }

    @Test("every restriction: the generated week passes the validator and uses only safe, fitting recipes")
    func everyRestrictionGeneratedWeek() throws {
        let seed = try F.seed()
        let planner = F.plannerLibrary(seed)
        let checker = F.checkLibrary(seed)
        var filled = 0
        for restriction in seed.catalog.restrictions {
            for scope in Scope.allCases {
                let rule = Rule(id: "rule-a", scope: scope.ruleScope, restriction: restriction, createdAt: F.now)
                let household = F.pair(rules: [rule])
                let clearance = try F.clearance(household)
                for planSeed in UInt64(0)..<2 {
                    let plan = try WeekPlanner.generateWeek(
                        clearance: clearance, household: household, library: planner,
                        request: F.request(seed: planSeed), signals: F.favouriteEverything(seed), now: F.now,
                        timeZone: F.utc)
                    let report = PlanValidator.validate(plan, household: household, library: checker)
                    #expect(report.passedForEveryone, "\(restriction.id) on \(scope): \(report.violations)")
                    #expect(plan.status == .draft)
                    #expect(plan.approval == nil)
                    for meal in plan.meals {
                        guard let recipeId = meal.recipeId else {
                            #expect(meal.emptyReason == .noSafeRecipe)
                            continue
                        }
                        let entry = try #require(planner.entry(recipeId))
                        #expect(HardFilter.fits(entry, slot: meal.slot), "\(recipeId) does not fit \(meal.slot)")
                        filled += 1
                    }
                }
            }
        }
        #expect(filled > 0)
    }

    /// How two restrictions are spread over the pair.
    enum PairPlacement: String, CaseIterable, Sendable {
        /// Both on the child (one person, two rules).
        case bothOnChild
        /// One on the child, one on the adult (lunchbox and family lunch have different eaters).
        case splitAcrossMembers
        /// One for the whole household, one on the child.
        case householdAndChild

        func rules(_ first: Restriction, _ second: Restriction) -> [Rule] {
            let scopes: (RuleScope, RuleScope)
            switch self {
            case .bothOnChild: scopes = (.member(F.child), .member(F.child))
            case .splitAcrossMembers: scopes = (.member(F.child), .member(F.adult))
            case .householdAndChild: scopes = (.household, .member(F.child))
            }
            return [
                Rule(id: "rule-a", scope: scopes.0, restriction: first, createdAt: F.now),
                Rule(id: "rule-b", scope: scopes.1, restriction: second, createdAt: F.now),
            ]
        }
    }

    @Test(
        "every restriction pair: filter, validator and oracle agree, and the week and its edits pass",
        arguments: PairPlacement.allCases)
    func everyRestrictionPair(placement: PairPlacement) throws {
        let seed = try F.seed()
        let planner = F.plannerLibrary(seed)
        let checker = F.checkLibrary(seed)
        let restrictions = seed.catalog.restrictions
        var total = F.Agreement()
        var pairs = 0
        for i in restrictions.indices {
            for j in restrictions.indices where j > i || (j < i && placement == .splitAcrossMembers) {
                // Split placements are not symmetric (which member gets which rule), so they
                // run in both orders; the others run each unordered pair once.
                let household = F.pair(rules: placement.rules(restrictions[i], restrictions[j]))
                let clearance = try F.clearance(household)
                let label = "\(restrictions[i].id) + \(restrictions[j].id) (\(placement))"
                total.merge(
                    F.agreement(
                        household: household, clearance: clearance, cases: F.pairCases, seed: seed,
                        planner: planner, checker: checker, label: label))

                let plan = try WeekPlanner.generateWeek(
                    clearance: clearance, household: household, library: planner,
                    request: F.request(seed: UInt64(i * 100 + j)), now: F.now, timeZone: F.utc)
                var plans = [plan]
                // The editing entry points on a sample of pairs (every pair would be slow in a
                // debug build); the generated households cover them further.
                if (i + j) % 4 == 0 {
                    plans += try F.editedPlans(plan, clearance: clearance, household: household, library: planner)
                }
                for checked in plans {
                    let report = PlanValidator.validate(checked, household: household, library: checker)
                    #expect(report.passedForEveryone, "\(label): \(report.violations)")
                }
                pairs += 1
            }
        }
        let n = restrictions.count
        #expect(pairs == (placement == .splitAcrossMembers ? n * (n - 1) : n * (n - 1) / 2))
        #expect(total.mismatches.isEmpty, "\(total.mismatches.count) disagreements: \(total.mismatches.prefix(20))")
        #expect(total.unsafe > 0)
    }
}
