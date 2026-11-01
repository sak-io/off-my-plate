import Foundation
import OMPDomain
import OMPRecipes
import OMPSafetyCheck
import Testing

/// Shared fixtures for the non-skippable safety suite (T12; ADR 0007; plan section 8).
///
/// The suite cross-checks three independent answers to "is this recipe safe for these eaters":
/// - the planner's hard filter (`HardFilter.isSafe`, over the planner's precomputed tag index),
/// - the independent validator (`PlanValidator`, recomputing tags from raw ingredient lines),
/// - an oracle written here from `SeedLibrary.derivedTags(of:)` and
///   `SeedLibrary.unverifiedIngredients(of:)` (the seed library's own derivation).
/// All three must agree on every case, and every plan the planner produces must pass the
/// validator. Nothing in this target may be disabled or marked as a known issue
/// (`scripts/lint-safety.sh`), and CI runs it as its own step (`core-linux.yml`).
enum SuiteFixture {
    static let utc = TimeZone(identifier: "UTC")!
    /// 2026-10-12T00:00:00Z, a Monday.
    static let now = Date(timeIntervalSince1970: 1_791_763_200)
    static let today = LocalDate(year: 2026, month: 10, day: 12)!
    static let day: TimeInterval = 86_400

    /// The bundled seed library, loaded once per call site (it is small: tens of recipes).
    static func seed() throws -> SeedLibrary {
        try SeedLoader.loadBundled()
    }

    static func plannerLibrary(_ seed: SeedLibrary) -> PlannerLibrary {
        PlannerLibrary(recipes: seed.recipes, ingredients: seed.ingredients, contentVersion: seed.contentVersion)
    }

    static func checkLibrary(_ seed: SeedLibrary) -> SafetyCheckLibrary {
        SafetyCheckLibrary(recipes: seed.recipes, ingredients: seed.ingredients)
    }

    // MARK: Fixed two-member household (adult + school child)

    static let adult: MemberID = "m-adult"
    static let child: MemberID = "m-child"

    /// An adult and a child who needs a school lunch Monday to Friday, both answered today.
    static func pair(rules: [Rule], snacks: Bool = true) -> Household {
        let status: SafetyStatus = rules.isEmpty ? .confirmedNone : .stated
        return Household(
            id: "household-suite",
            members: [
                Member(
                    id: adult, label: MemberLabel(role: .adult, number: 1), ageBand: .adult, safetyStatus: status,
                    safetyConfirmedAt: now),
                Member(
                    id: child, label: MemberLabel(role: .child, number: 1), ageBand: .child, safetyStatus: status,
                    safetyConfirmedAt: now, needsSchoolLunch: true, schoolDays: Weekday.schoolWeek),
            ],
            rules: rules, settings: HouseholdSettings(snacksEnabled: snacks), createdAt: now, updatedAt: now)
    }

    /// The servings `SlotExpansion` gives the fixed pair on a school day: the lunchbox is the
    /// child's only, family lunch is the adult's only, every other slot is shared.
    static func pairServings(for slot: MealSlot) -> [MealServing] {
        let adultEats = slot != .lunchbox
        let childEats = slot != .lunch
        return [
            MealServing(memberId: adult, portion: 1.0, notEating: !adultEats),
            MealServing(memberId: child, portion: 0.6, notEating: !childEats),
        ]
    }

    // MARK: Oracle

    /// The suite's own answer, from the seed library's derivation: safe unless some eater with a
    /// hard rule meets an unverified ingredient or one of their excluded tags.
    static func oracleSafe(_ recipe: Recipe, eaterIDs: [MemberID], household: Household, seed: SeedLibrary) -> Bool {
        let tags = seed.derivedTags(of: recipe)
        let unverified = !seed.unverifiedIngredients(of: recipe).isEmpty
        for eater in eaterIDs {
            let rules = household.rules(covering: eater).filter { $0.kind == .hard }
            if rules.isEmpty {
                continue
            }
            if unverified {
                return false
            }
            if rules.contains(where: { !$0.excludedTags.isDisjoint(with: tags) }) {
                return false
            }
        }
        return true
    }

    // MARK: Agreement matrix

    /// One way a meal can be eaten: a slot and a full serving list (who eats, who does not).
    struct EatingCase: Hashable {
        var slot: MealSlot
        var servings: [MealServing]

        var eaterIDs: [MemberID] {
            servings.filter { !$0.notEating }.map(\.memberId)
        }
    }

    /// Outcome of an agreement check: how many cases were safe and unsafe, and every
    /// disagreement in readable form.
    struct Agreement {
        var safe = 0
        var unsafe = 0
        var mismatches: [String] = []

        mutating func merge(_ other: Agreement) {
            safe += other.safe
            unsafe += other.unsafe
            mismatches += other.mismatches
        }
    }

    /// Checks every seed recipe in every eating case with the three independent paths.
    ///
    /// Builds one plan holding a meal per (recipe, case) so the validator runs once per
    /// household, then compares its verdict per meal with `HardFilter.isSafe` and the oracle.
    /// Also checks that `HardFilter.candidates` for each case is exactly the recipes that fit
    /// the slot and that the validator passes.
    static func agreement(
        household: Household, clearance: SafetyClearance, cases: [EatingCase], seed: SeedLibrary,
        planner: PlannerLibrary, checker: SafetyCheckLibrary, label: String
    ) -> Agreement {
        struct Cell {
            var mealID: PlannedMealID
            var recipe: Recipe
            var eatingCase: EatingCase
        }
        var cells: [Cell] = []
        var meals: [PlannedMeal] = []
        for (caseIndex, eatingCase) in cases.enumerated() {
            for recipe in seed.recipes {
                let mealID = PlannedMealID("m\(caseIndex)-\(eatingCase.slot.rawValue)-\(recipe.id.rawValue)")
                cells.append(Cell(mealID: mealID, recipe: recipe, eatingCase: eatingCase))
                meals.append(
                    PlannedMeal(
                        id: mealID, date: today, slot: eatingCase.slot, recipeId: recipe.id,
                        servings: eatingCase.servings))
            }
        }
        let plan = MealPlan(
            id: "matrix", seriesId: "matrix", weekStart: today, meals: meals, contentVersion: seed.contentVersion,
            createdAt: now)
        let report = PlanValidator.validate(plan, household: household, library: checker)
        let violating = Set(report.violatingMealIDs)

        var result = Agreement()
        var expectedCandidates: [EatingCase: [RecipeID]] = [:]
        for cell in cells {
            let eaters = cell.eatingCase.eaterIDs
            let validatorSafe = !violating.contains(cell.mealID)
            let oracle = oracleSafe(cell.recipe, eaterIDs: eaters, household: household, seed: seed)
            guard let entry = planner.entry(cell.recipe.id) else {
                result.mismatches.append("\(label): \(cell.recipe.id) missing from the planner library")
                continue
            }
            let filterSafe = HardFilter.isSafe(entry, eaterIDs: eaters, clearance: clearance)
            if filterSafe != validatorSafe || filterSafe != oracle {
                result.mismatches.append(
                    "\(label): \(cell.recipe.id) \(cell.eatingCase.slot) eaters \(eaters.map(\.rawValue)): "
                        + "filter \(filterSafe), validator \(validatorSafe), oracle \(oracle)")
            }
            if validatorSafe {
                result.safe += 1
            } else {
                result.unsafe += 1
            }
            if validatorSafe && HardFilter.fits(entry, slot: cell.eatingCase.slot) {
                expectedCandidates[cell.eatingCase, default: []].append(cell.recipe.id)
            }
        }
        for eatingCase in Set(cases) {
            let candidates = HardFilter.candidates(
                for: eatingCase.slot, eaterIDs: eatingCase.eaterIDs, library: planner, clearance: clearance
            ).map(\.id)
            let expected = (expectedCandidates[eatingCase] ?? []).sorted()
            if candidates != expected {
                result.mismatches.append(
                    "\(label): candidates for \(eatingCase.slot) \(eatingCase.eaterIDs.map(\.rawValue)) "
                        + "\(candidates.map(\.rawValue)) != validator-safe \(expected.map(\.rawValue))")
            }
        }
        return result
    }

    /// Every eating case of the fixed pair, one per slot.
    static var pairCases: [EatingCase] {
        MealSlot.allCases.map { EatingCase(slot: $0, servings: pairServings(for: $0)) }
    }

    // MARK: Planning helpers

    static func clearance(_ household: Household, at instant: Date = now) throws -> SafetyClearance {
        try SafetyGate.evaluate(household, now: instant, timeZone: utc).get()
    }

    static func request(
        seed: UInt64, weekStart: LocalDate = today, absences: Set<MealAbsence> = []
    ) -> WeekPlanRequest {
        WeekPlanRequest(
            planId: "plan-suite", seriesId: "series-suite", weekStart: weekStart, absences: absences,
            seed: PlannerSeed(seed))
    }

    /// Every plan the editing entry points can produce from `plan`: each meal swapped to each
    /// alternative, each meal re-rolled with each reason, and a regenerate with every third
    /// meal locked. The meals of the swapped and re-rolled plans keep their ids, so a validator
    /// violation still names the meal it came from.
    static func editedPlans(
        _ plan: MealPlan, clearance: SafetyClearance, household: Household, library: PlannerLibrary,
        signals: PlannerSignals = PlannerSignals(), at instant: Date = now
    ) throws -> [MealPlan] {
        let reasons: [RerollReason?] = [nil] + RerollReason.allCases.map { Optional($0) }
        var swapped: [PlannedMeal] = []
        var rerolled: [PlannedMeal] = []
        for meal in plan.meals where !meal.locked {
            let alternatives = try WeekPlanner.alternatives(
                for: meal.id, in: plan, clearance: clearance, household: household, library: library,
                signals: signals, now: instant, timeZone: utc)
            #expect(alternatives.count <= 3)
            swapped += alternatives.map { meal.replacingRecipe(with: $0) }
            for reason in reasons {
                if let replacement = try WeekPlanner.reroll(
                    meal.id, in: plan, reason: reason, clearance: clearance, household: household, library: library,
                    signals: signals, now: instant, timeZone: utc)
                {
                    rerolled.append(replacement)
                }
            }
        }
        var swappedPlan = plan
        swappedPlan.meals = swapped
        var rerolledPlan = plan
        rerolledPlan.meals = rerolled

        var locked = plan
        for index in locked.meals.indices where index % 3 == 0 {
            locked.meals[index].locked = true
        }
        var regenerated = locked
        regenerated.meals = try WeekPlanner.regenerate(
            locked, clearance: clearance, household: household, library: library, signals: signals, now: instant,
            timeZone: utc)
        return [swappedPlan, rerolledPlan, regenerated]
    }

    /// Soft signals that favour every recipe, so scoring pressure is maximal; they must never
    /// beat the hard filter.
    static func favouriteEverything(_ seed: SeedLibrary) -> PlannerSignals {
        PlannerSignals(
            facts: seed.recipes.map {
                Fact(
                    id: FactID("fav-" + $0.id.rawValue), statement: .favouriteRecipe($0.id), origin: .stated,
                    confidence: 1, status: .active, createdAt: now, updatedAt: now)
            })
    }

    /// The error a planner call threw, or `nil` if it returned.
    static func plannerError(_ body: () throws -> Void) -> PlannerError? {
        do {
            try body()
            return nil
        } catch let error as PlannerError {
            return error
        } catch {
            Issue.record("unexpected error: \(error)")
            return nil
        }
    }
}
