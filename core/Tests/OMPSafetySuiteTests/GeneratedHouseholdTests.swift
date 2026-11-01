import Foundation
import OMPDomain
import OMPRecipes
import OMPSafetyCheck
import Testing

/// Deterministically generated households: random members, age bands, school lunches, deleted
/// members, catalog and ad-hoc hard rules, snacks, absences and start dates.
enum HouseholdGenerator {
    typealias F = SuiteFixture

    /// What one generated case plans with.
    struct Case {
        var household: Household
        var request: WeekPlanRequest
        var signals: PlannerSignals
    }

    static func make(index: Int, seed: SeedLibrary) -> Case {
        var rng = SplitMix64(seed: SplitMix64.mix(0x5AFE_7E57 &+ UInt64(index)))
        func chance(_ percent: Int) -> Bool { rng.nextIndex(below: 100) < percent }
        func pick<T>(_ items: [T]) -> T { items[rng.nextIndex(below: items.count)] }

        let ageBands: [AgeBand?] = [nil] + AgeBand.allCases.map { Optional($0) }
        let childBands: Set<AgeBand> = [.infant, .toddler, .child, .teen]
        let memberCount = 1 + rng.nextIndex(below: 6)
        var members: [Member] = []
        for number in 1...memberCount {
            let ageBand = pick(ageBands)
            let isChild = ageBand.map { childBands.contains($0) } ?? false
            let schoolDays = Set(Weekday.allCases.filter { _ in chance(60) })
            members.append(
                Member(
                    id: MemberID("g\(index)-m\(number)"),
                    label: MemberLabel(role: isChild ? .child : .adult, number: number), ageBand: ageBand,
                    safetyStatus: .confirmedNone,
                    // Answered between 0 and 180 days ago: still in date.
                    safetyConfirmedAt: F.now - Double(rng.nextIndex(below: 181)) * F.day,
                    needsSchoolLunch: isChild && chance(70), schoolDays: schoolDays,
                    portionOverride: chance(10) ? 1.5 : nil))
        }
        // Sometimes a deleted, never-asked member (sometimes with a rule): never blocks, never eats.
        let deletedID = MemberID("g\(index)-deleted")
        if chance(20) {
            members.append(
                Member(
                    id: deletedID, label: MemberLabel(role: .adult, number: memberCount + 1), safetyStatus: .unasked,
                    deletedAt: F.now - F.day))
        }

        var rules: [Rule] = []
        let restrictions = seed.catalog.restrictions
        for ruleNumber in 0..<rng.nextIndex(below: 4) {
            let scope: RuleScope =
                chance(30) ? .household : .member(members[rng.nextIndex(below: memberCount)].id)
            let ruleID = RuleID("g\(index)-r\(ruleNumber)")
            if chance(80) {
                rules.append(Rule(id: ruleID, scope: scope, restriction: pick(restrictions), createdAt: F.now))
            } else {
                // An ad-hoc tag set beyond the catalog's restrictions.
                let tags = Set(FoodTag.allCases.filter { _ in chance(15) })
                rules.append(
                    Rule(id: ruleID, scope: scope, restriction: "adhoc", excludedTags: tags, createdAt: F.now))
            }
        }
        if chance(20) {
            rules.append(
                Rule(
                    id: RuleID("g\(index)-deleted-rule"), scope: .member(deletedID), restriction: pick(restrictions),
                    createdAt: F.now))
        }
        for i in members.indices where !members[i].isDeleted {
            let covered = rules.contains { $0.scope.covers(members[i].id) }
            members[i].safetyStatus = covered ? .stated : .confirmedNone
        }

        let household = Household(
            id: HouseholdID("household-g\(index)"), members: members, rules: rules,
            settings: HouseholdSettings(snacksEnabled: chance(40)), createdAt: F.now, updatedAt: F.now)

        let weekStart = F.today.adding(days: rng.nextIndex(below: 7))
        var absences = Set<MealAbsence>()
        for _ in 0..<rng.nextIndex(below: 5) {
            absences.insert(
                MealAbsence(
                    memberId: members[rng.nextIndex(below: memberCount)].id,
                    date: weekStart.adding(days: rng.nextIndex(below: MealPlan.lengthInDays)),
                    slot: pick(MealSlot.allCases)))
        }
        let request = WeekPlanRequest(
            planId: MealPlanID("plan-g\(index)"), seriesId: PlanSeriesID("series-g\(index)"), weekStart: weekStart,
            absences: absences, seed: PlannerSeed(rng.next()))
        let signals = chance(50) ? F.favouriteEverything(seed) : PlannerSignals()
        return Case(household: household, request: request, signals: signals)
    }
}

/// The parameterised batches of `GeneratedHouseholdTests` (Swift Testing runs them in parallel).
private let generatedBatches = 0..<10

/// 500 seeded generated households (T12; AC-4.1, AC-4.3, AC-4.5, AC-6.3, AC-3.1; ADR 0007).
@Suite("Safety suite: 500 generated households")
struct GeneratedHouseholdTests {
    typealias F = SuiteFixture
    typealias G = HouseholdGenerator

    static let householdCount = 500
    static let batchCount = generatedBatches.count
    /// Every `editingStride`-th household also runs swap, re-roll and regenerate.
    static let editingStride = 5

    @Test("the batches cover exactly 500 distinct households")
    func batchesCoverEveryHousehold() {
        let indices = (0..<Self.batchCount).flatMap { Self.indices(batch: $0) }
        #expect(indices.count == Self.householdCount)
        #expect(Set(indices).count == Self.householdCount)
    }

    static func indices(batch: Int) -> [Int] {
        Array(stride(from: batch, to: householdCount, by: batchCount))
    }

    @Test(
        "generated households: cleared, every plan and edit passes the validator, filter and validator agree",
        arguments: generatedBatches)
    func generatedHouseholds(batch: Int) throws {
        let seed = try F.seed()
        let planner = F.plannerLibrary(seed)
        let checker = F.checkLibrary(seed)
        var total = F.Agreement()
        var filled = 0
        for index in Self.indices(batch: batch) {
            let generated = G.make(index: index, seed: seed)
            let household = generated.household
            let label = "household \(index)"

            // An answered, in-date household is cleared, and the clearance holds only active members.
            let clearance = try F.clearance(household)
            #expect(clearance.members.map(\.id) == household.activeMembers.map(\.id), "\(label)")

            let plan = try WeekPlanner.generateWeek(
                clearance: clearance, household: household, library: planner, request: generated.request,
                signals: generated.signals, now: F.now, timeZone: F.utc)
            let report = PlanValidator.validate(plan, household: household, library: checker)
            #expect(report.passedForEveryone, "\(label): \(report.violations)")
            filled += plan.meals.filter { $0.recipeId != nil }.count

            // Filter vs validator vs oracle on every distinct way this week's meals are eaten.
            let cases = Set(plan.meals.map { F.EatingCase(slot: $0.slot, servings: $0.servings) })
            total.merge(
                F.agreement(
                    household: household, clearance: clearance, cases: cases.sorted { "\($0)" < "\($1)" },
                    seed: seed, planner: planner, checker: checker, label: label))

            if index % Self.editingStride == 0 {
                for edited in try F.editedPlans(
                    plan, clearance: clearance, household: household, library: planner, signals: generated.signals)
                {
                    let editedReport = PlanValidator.validate(edited, household: household, library: checker)
                    #expect(editedReport.passedForEveryone, "\(label) (edited): \(editedReport.violations)")
                }
            }

            try checkGateRefusals(household: household, clearance: clearance, generated: generated, planner: planner)
        }
        #expect(total.mismatches.isEmpty, "\(total.mismatches.count) disagreements: \(total.mismatches.prefix(20))")
        #expect(filled > 0)
    }

    /// The same household with one member reset to `unasked`, and the same household 181 days
    /// later: the gate refuses, and the earlier clearance no longer plans.
    private func checkGateRefusals(
        household: Household, clearance: SafetyClearance, generated: G.Case, planner: PlannerLibrary
    ) throws {
        let active = household.members.indices.filter { !household.members[$0].isDeleted }
        let target = try #require(active.last)
        var unasked = household
        unasked.members[target].safetyStatus = .unasked
        unasked.members[target].safetyConfirmedAt = nil
        let unaskedID = unasked.members[target].id
        guard case .failure(.safetyUnanswered(let ids)) = SafetyGate.evaluate(unasked, now: F.now, timeZone: F.utc)
        else {
            Issue.record("\(household.id): the gate did not refuse an unasked member")
            return
        }
        #expect(ids == [unaskedID])

        let later = F.now + 181 * F.day
        guard case .failure(.reconfirmationDue(let due)) = SafetyGate.evaluate(household, now: later, timeZone: F.utc)
        else {
            Issue.record("\(household.id): the gate did not refuse overdue answers")
            return
        }
        #expect(due == household.activeMembers.map(\.id))

        for (stale, instant) in [(unasked, F.now), (household, later)] {
            let error = F.plannerError {
                _ = try WeekPlanner.generateWeek(
                    clearance: clearance, household: stale, library: planner, request: generated.request,
                    now: instant, timeZone: F.utc)
            }
            #expect(error == .clearanceNotValid)
        }
    }
}
