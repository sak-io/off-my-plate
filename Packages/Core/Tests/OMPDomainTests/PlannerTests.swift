import Foundation
import OMPDomain
import Testing

private typealias P = PlannerFixture

/// The error `body` throws as a `PlannerError`, or `nil` if it succeeds.
private func plannerError(_ body: () throws -> MealPlan) -> PlannerError? {
    do {
        _ = try body()
        return nil
    } catch let error as PlannerError {
        return error
    } catch {
        Issue.record("unexpected error: \(error)")
        return nil
    }
}

@Suite("WeekPlanner.generateWeek: clearance (ADR 0007, T08 review-2)")
struct PlannerClearanceTests {
    @Test("a valid clearance plans a draft")
    func validClearancePlans() throws {
        let plan = try P.generate(P.household())
        #expect(plan.status == .draft)
        #expect(plan.approval == nil)
    }

    @Test("refuses a clearance whose household changed after the gate ran (stale)")
    func refusesStaleClearance() throws {
        let household = P.household()
        let clearance = try P.clearance(household)
        var edited = household
        edited.rules.append(P.rule("peanuts", .member(P.child), [.peanut]))
        let error = plannerError {
            try WeekPlanner.generateWeek(
                clearance: clearance, household: edited, library: P.library, request: P.request(), now: P.now,
                timeZone: P.utc)
        }
        #expect(error == .clearanceNotValid)
    }

    @Test("refuses a clearance for a different household")
    func refusesOtherHousehold() throws {
        let clearance = try P.clearance(P.household())
        let other = Household(
            id: "household-2", members: P.household().members, createdAt: P.now, updatedAt: P.now)
        let error = plannerError {
            try WeekPlanner.generateWeek(
                clearance: clearance, household: other, library: P.library, request: P.request(), now: P.now,
                timeZone: P.utc)
        }
        #expect(error == .clearanceNotValid)
    }

    @Test("refuses an old clearance once a re-confirmation has fallen due (day 181)")
    func refusesOverdueClearance() throws {
        let household = P.household()
        let clearance = try P.clearance(household)
        let error = plannerError {
            try WeekPlanner.generateWeek(
                clearance: clearance, household: household, library: P.library, request: P.request(),
                now: P.now + 181 * P.day, timeZone: P.utc)
        }
        #expect(error == .clearanceNotValid)
    }
}

@Suite("WeekPlanner: slots and servings (AC-6.1, AC-6.2, AC-6.3, AC-7.2, R7, R8, G5)")
struct PlannerSlotTests {
    @Test("AC-6.1/R8: 7 days from the start date with breakfast, lunch and dinner; no snacks by default")
    func sevenDaysThreeSlots() throws {
        let plan = try P.generate(P.household())
        #expect(plan.weekStart == P.monday)
        #expect(plan.id == "plan-1")
        #expect(plan.seriesId == "series-1")
        #expect(plan.revision == 1)
        #expect(plan.contentVersion == "seed-test")
        #expect(plan.createdAt == P.now)
        #expect(plan.meals.count == 21)
        for (index, date) in plan.dates.enumerated() {
            let slots = plan.meals.filter { $0.date == date }.map(\.slot)
            #expect(slots == [.breakfast, .lunch, .dinner], "day \(index)")
        }
        #expect(Set(plan.meals.map(\.id)).count == plan.meals.count)
        #expect(plan.meals.allSatisfy { $0.recipeId != nil && $0.emptyReason == nil })
    }

    @Test("G5: a snack slot is added on every day when the household enables snacks")
    func snacksWhenEnabled() throws {
        let plan = try P.generate(P.household(snacks: true))
        #expect(P.meals(plan, .snack).count == 7)
        #expect(plan.meals.count == 28)
    }

    @Test("AC-6.2: each member gets their default portion (age band or override)")
    func defaultPortions() throws {
        let plan = try P.generate(P.household(childPortionOverride: 0.8))
        for meal in plan.meals {
            let expected = [MealServing(memberId: P.adult, portion: 1.0), MealServing(memberId: P.child, portion: 0.8)]
            #expect(meal.servings == expected)
        }
        let plain = try P.generate(P.household())
        #expect(plain.meals[0].servings.map(\.portion) == [1.0, 0.6])
    }

    @Test("AC-7.2/R7: a lunchbox on school days only; lunchbox child is off family lunch those days")
    func lunchboxSlots() throws {
        let plan = try P.generate(P.household(lunchbox: true))
        let lunchboxes = P.meals(plan, .lunchbox)
        // 2026-10-12 is a Monday: Monday to Friday are the first five days.
        #expect(lunchboxes.map(\.date) == Array(plan.dates.prefix(5)))
        for meal in lunchboxes {
            #expect(meal.eaterIDs == [P.child])
            #expect(meal.servings.count == 2)
        }
        for meal in P.meals(plan, .lunch) {
            let schoolDay = meal.date.weekday < .saturday
            #expect(meal.eaterIDs == (schoolDay ? [P.adult] : [P.adult, P.child]), "\(meal.date)")
        }
        // The lunchbox is filled before family lunch within a day.
        let monday = plan.meals.filter { $0.date == P.monday }.map(\.slot)
        #expect(monday == [.breakfast, .lunchbox, .lunch, .dinner])
    }

    @Test("AC-7.2: lunchboxes are filled only from lunchbox-suitable recipes")
    func lunchboxOnlySuitable() throws {
        let suitable = Set(P.recipes.filter(\.lunchboxSuitable).map(\.id))
        for seed in UInt64(0)..<20 {
            let plan = try P.generate(P.household(lunchbox: true), seed: PlannerSeed(seed))
            for meal in P.meals(plan, .lunchbox) {
                let id = try #require(meal.recipeId)
                #expect(suitable.contains(id))
            }
        }
        // With no suitable recipe at all, lunchboxes stay empty instead of using a lunch recipe.
        let noLunchbox = P.makeLibrary(P.recipes.filter { !$0.lunchboxSuitable })
        let plan = try P.generate(P.household(lunchbox: true), library: noLunchbox)
        #expect(P.meals(plan, .lunchbox).allSatisfy { $0.recipeId == nil && $0.emptyReason == .noSafeRecipe })
    }

    @Test("AC-6.3: a member marked not eating gets a notEating serving and does not constrain the slot")
    func notEatingMember() throws {
        let household = P.household(rules: [P.rule("peanuts", .member(P.child), [.peanut])])
        let library = P.makeLibrary([P.recipe("d-peanut-curry", [.dinner], ["peanuts", "rice"])])
        let absence = MealAbsence(memberId: P.child, date: P.monday, slot: .dinner)
        let plan = try P.generate(household, library: library, absences: [absence])
        let dinners = P.meals(plan, .dinner)
        #expect(dinners[0].recipeId == "d-peanut-curry")
        #expect(dinners[0].eaterIDs == [P.adult])
        #expect(dinners[0].servings.first { $0.memberId == P.child }?.notEating == true)
        for meal in dinners.dropFirst() {
            #expect(meal.recipeId == nil)
            #expect(meal.emptyReason == .noSafeRecipe)
        }
    }

    @Test("R8: the first plan starts today; the next starts the day after the previous ends")
    func dateRange() {
        let today = P.monday
        #expect(PlanDateRange.startDate(previousEnd: nil, today: today) == today)
        let previousEnd = today.adding(days: 3)
        #expect(PlanDateRange.startDate(previousEnd: previousEnd, today: today) == today.adding(days: 4))
        // A previous plan that ended in the past never makes a plan start before today.
        #expect(PlanDateRange.startDate(previousEnd: today.adding(days: -10), today: today) == today)
        #expect(PlanDateRange.dates(from: today) == (0..<7).map { today.adding(days: $0) })
    }
}

@Suite("WeekPlanner: hard filter (AC-4.1, AC-4.3, AC-4.4)")
struct PlannerHardFilterTests {
    private func candidateIDs(_ household: Household, slot: MealSlot = .dinner, absent: Set<MemberID> = [])
        throws -> [RecipeID]
    {
        let clearance = try P.clearance(household)
        let servings = clearance.members.map {
            MealServing(memberId: $0.id, portion: $0.defaultPortion, notEating: absent.contains($0.id))
        }
        let plannerSlot = PlannerSlot(date: P.monday, slot: slot, servings: servings)
        return HardFilter.candidates(for: plannerSlot, library: P.library, clearance: clearance).map(\.id)
    }

    @Test("with no rules every complete recipe of the meal type is a candidate, unverified included")
    func noRules() throws {
        #expect(try candidateIDs(P.household()) == ["d-chapati-sabzi", "d-dal-tadka", "d-egg-curry", "d-veg-pulao"])
        #expect(try candidateIDs(P.household(), slot: .snack) == ["s-banana", "s-chana", "s-masala-chana"])
    }

    @Test("an ingredient missing from the taxonomy excludes the recipe for everyone (fail closed)")
    func unknownIngredient() throws {
        #expect(try !candidateIDs(P.household()).contains("d-ghost"))
    }

    @Test("may-contain tags on optional lines count: a wheat rule excludes dal tadka (hing)")
    func mayContainOnOptionalLine() throws {
        let household = P.household(rules: [P.rule("wheat", .member(P.adult), [.wheat, .gluten])])
        #expect(try candidateIDs(household) == ["d-egg-curry", "d-veg-pulao"])
        // The same rule does not constrain the slot when its member is not eating.
        #expect(try candidateIDs(household, absent: [P.adult]).contains("d-dal-tadka"))
    }

    @Test("tags come from ingredients, not declaredTags")
    func ignoresDeclaredTags() throws {
        let household = P.household(rules: [P.rule("peanuts", .member(P.child), [.peanut])])
        let sneaky = P.recipe("d-sneaky", [.dinner], ["peanuts"], declared: [])
        let library = P.makeLibrary([sneaky])
        let plan = try P.generate(household, library: library)
        #expect(P.meals(plan, .dinner).allSatisfy { $0.recipeId == nil })
    }

    @Test("AC-4.3: an unverified ingredient excludes the recipe when any eater has any hard rule")
    func unverifiedIngredient() throws {
        let household = P.household(rules: [P.rule("egg", .member(P.child), [.egg])])
        #expect(try candidateIDs(household, slot: .snack) == ["s-banana", "s-chana"])
        // Nobody with a rule is eating: the unverified recipe is allowed again.
        #expect(try candidateIDs(household, slot: .snack, absent: [P.child]).contains("s-masala-chana"))
    }

    @Test("a household-scope rule protects every eater")
    func householdScope() throws {
        let household = P.household(rules: [P.rule("milk", .household, [.milk])])
        #expect(try candidateIDs(household) == ["d-chapati-sabzi", "d-egg-curry", "d-veg-pulao"])
        #expect(try candidateIDs(household, slot: .lunch) == ["l-rajma", "l-sambar-rice"])
    }

    @Test("AC-4.1: generated meals never contain an excluded tag for an eater")
    func generatedMealsRespectRules() throws {
        let household = P.household(
            rules: [P.rule("peanuts", .member(P.child), [.peanut]), P.rule("egg", .household, [.egg])],
            snacks: true, lunchbox: true)
        let tagsByRecipe = Dictionary(uniqueKeysWithValues: P.library.entries.map { ($0.id, $0.containedTags) })
        for seed in UInt64(0)..<20 {
            let plan = try P.generate(household, seed: PlannerSeed(seed))
            for meal in plan.meals {
                guard let id = meal.recipeId else { continue }
                let tags = try #require(tagsByRecipe[id])
                #expect(!tags.contains(.egg))
                if meal.eaterIDs.contains(P.child) {
                    #expect(!tags.contains(.peanut), "\(meal.id)")
                }
                #expect(id != "s-masala-chana")
            }
        }
    }

    @Test("AC-4.4: with no safe recipe the slot is empty with .noSafeRecipe, never filled")
    func emptySlotWithReason() throws {
        let household = P.household(rules: [P.rule("peanuts", .member(P.child), [.peanut])])
        let library = P.makeLibrary([
            P.recipe("b-poha", [.breakfast], ["poha-flakes", "peanuts"], optional: ["peanuts"]),
            P.recipe("d-veg-pulao", [.dinner], ["rice", "vegetables"]),
        ])
        let plan = try P.generate(household, library: library)
        #expect(plan.meals.count == 21)
        for meal in P.meals(plan, .breakfast) + P.meals(plan, .lunch) {
            #expect(meal.recipeId == nil)
            #expect(meal.emptyReason == .noSafeRecipe)
            #expect(meal.reasons == [])
            #expect(meal.servings.count == 2)
        }
        #expect(P.meals(plan, .dinner).allSatisfy { $0.recipeId == "d-veg-pulao" })
    }
}

@Suite("WeekPlanner: selection, variety and determinism (AC-4.6, G5, ADR 0009)")
struct PlannerSelectionTests {
    @Test("AC-4.6: the same inputs and seed give an identical plan")
    func deterministic() throws {
        let household = P.household(rules: [P.rule("milk", .member(P.child), [.milk])], snacks: true, lunchbox: true)
        let seeds: [PlannerSeed?] = [PlannerSeed(0), PlannerSeed(7), PlannerSeed(UInt64.max), nil]
        for seed in seeds {
            let first = try P.generate(household, seed: seed)
            let second = try P.generate(household, seed: seed)
            #expect(first == second)
            #expect(first.contentHash == second.contentHash)
        }
    }

    @Test("different seeds can break ties differently")
    func seedsMatter() throws {
        let household = P.household()
        let reference = try P.generate(household, seed: PlannerSeed(0))
        var sawDifferent = false
        for seed in UInt64(1)..<20 {
            let plan = try P.generate(household, seed: PlannerSeed(seed))
            if plan != reference {
                sawDifferent = true
            }
        }
        #expect(sawDifferent)
    }

    @Test("the default seed is derived from household id, start date and revision (stable golden)")
    func derivedSeed() {
        let seed = PlannerSeed.derived(householdID: "household-1", weekStart: P.monday, revision: 1)
        // First 8 bytes (big-endian) of SHA-256("household-1|2026-10-12|1").
        #expect(seed.value == 13_690_792_653_361_547_541)
        #expect(PlannerSeed.derived(householdID: "household-1", weekStart: P.monday, revision: 2) != seed)
    }

    @Test("G5: with enough recipes no recipe repeats within 3 days and no relaxation reason appears")
    func varietyRespected() throws {
        for seed in UInt64(0)..<20 {
            let plan = try P.generate(P.household(snacks: true, lunchbox: true), seed: PlannerSeed(seed))
            var uses: [RecipeID: [LocalDate]] = [:]
            for meal in plan.meals {
                let id = try #require(meal.recipeId)
                uses[id, default: []].append(meal.date)
                #expect(!meal.reasons.contains(.repeatedFewSafeOptions))
            }
            for (id, dates) in uses {
                for (i, a) in dates.enumerated() {
                    for b in dates[(i + 1)...] {
                        #expect(abs(b.daysSince(a)) >= WeekPlanner.varietyWindowDays, "\(id) on \(a) and \(b)")
                    }
                }
            }
        }
    }

    @Test("G5: a single safe recipe repeats daily with the .repeatedFewSafeOptions reason")
    func varietyRelaxedSingleRecipe() throws {
        let library = P.makeLibrary([P.recipe("d-veg-pulao", [.dinner], ["rice", "vegetables"])])
        let dinners = try P.meals(P.generate(P.household(), library: library), .dinner)
        #expect(dinners.allSatisfy { $0.recipeId == "d-veg-pulao" })
        #expect(!dinners[0].reasons.contains(.repeatedFewSafeOptions))
        // T11: the relaxation note comes first, then the best real score reason (weekday dinners
        // of 30 minutes are quick weekday dinners; weekends have none).
        for meal in dinners.dropFirst() {
            let weekday = PlannerScoring.weekdays.contains(meal.date.weekday)
            let expected: [ExplanationReason] =
                weekday ? [.repeatedFewSafeOptions, .quickWeekday(.dinner)] : [.repeatedFewSafeOptions]
            #expect(meal.reasons == expected)
        }
    }

    @Test("G5: relaxation picks the least recently used recipe (two recipes alternate)")
    func varietyRelaxedAlternates() throws {
        let library = P.makeLibrary([
            P.recipe("d-veg-pulao", [.dinner], ["rice", "vegetables"]),
            P.recipe("d-chapati-sabzi", [.dinner], ["atta", "vegetables"]),
        ])
        for seed in UInt64(0)..<10 {
            let dinners = try P.meals(P.generate(P.household(), library: library, seed: PlannerSeed(seed)), .dinner)
            #expect(dinners[0].recipeId != dinners[1].recipeId)
            #expect(!dinners[0].reasons.contains(.repeatedFewSafeOptions))
            #expect(!dinners[1].reasons.contains(.repeatedFewSafeOptions))
            for index in 2..<dinners.count {
                #expect(dinners[index].recipeId == dinners[index - 2].recipeId)
                #expect(dinners[index].reasons.first == .repeatedFewSafeOptions)
            }
        }
    }
}

@Suite("SplitMix64")
struct SplitMix64Tests {
    @Test("matches the reference SplitMix64 output")
    func referenceVectors() {
        var zero = SplitMix64(seed: 0)
        #expect(zero.next() == 0xE220_A839_7B1D_CDAF)
        #expect(zero.next() == 0x6E78_9E6A_A1B9_65F4)
        #expect(zero.next() == 0x06C4_5D18_8009_454F)
        var other = SplitMix64(seed: 1_234_567)
        #expect(other.next() == 0x599E_D017_FB08_FC85)
        #expect(other.next() == 0x2C73_F084_5854_0FA5)
    }

    @Test("nextIndex stays in range and covers every index")
    func nextIndexRange() {
        var rng = SplitMix64(seed: 99)
        var seen = Set<Int>()
        for _ in 0..<500 {
            let index = rng.nextIndex(below: 5)
            #expect((0..<5).contains(index))
            seen.insert(index)
        }
        #expect(seen == Set(0..<5))
        #expect(rng.nextIndex(below: 1) == 0)
    }
}
