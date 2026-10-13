import Foundation

/// Why the planner refused to plan (ADR 0007).
public enum PlannerError: Error, Sendable, Hashable {
    /// The clearance does not match the household any more, or the safety gate no longer passes
    /// at `now` (for example a re-confirmation fell due). Run the gate again.
    case clearanceNotValid
}

/// The seed for the planner's deterministic tie-breaks (ADR 0009, AC-4.6).
public struct PlannerSeed: Codable, Sendable, Hashable {
    public var value: UInt64

    public init(_ value: UInt64) {
        self.value = value
    }

    /// The default seed for a plan: derived from the household id, the plan's start date and
    /// its revision (ADR 0009), through SHA-256 so it is the same on every platform and run
    /// (Swift's `Hasher` is randomly seeded per process, so it must not be used here).
    public static func derived(householdID: HouseholdID, weekStart: LocalDate, revision: Int) -> PlannerSeed {
        let text = householdID.rawValue + "|" + weekStart.isoString + "|" + String(revision)
        let digest = SHA256.hash(Array(text.utf8))
        var value: UInt64 = 0
        for byte in digest.prefix(8) {
            value = (value << 8) | UInt64(byte)
        }
        return PlannerSeed(value)
    }
}

/// What to plan: identifiers, dates and per-meal absences (plan section 5 step 1).
public struct WeekPlanRequest: Sendable, Hashable {
    public var planId: MealPlanID
    public var seriesId: PlanSeriesID
    public var revision: Int
    public var basedOn: MealPlanID?
    /// First day of the plan (see `PlanDateRange.startDate(previousEnd:today:)`, R8).
    public var weekStart: LocalDate
    /// Members marked "not eating" for specific meals (AC-6.3).
    public var absences: Set<MealAbsence>
    /// `nil` uses `PlannerSeed.derived(householdID:weekStart:revision:)`.
    public var seed: PlannerSeed?

    public init(
        planId: MealPlanID,
        seriesId: PlanSeriesID,
        revision: Int = 1,
        basedOn: MealPlanID? = nil,
        weekStart: LocalDate,
        absences: Set<MealAbsence> = [],
        seed: PlannerSeed? = nil
    ) {
        self.planId = planId
        self.seriesId = seriesId
        self.revision = revision
        self.basedOn = basedOn
        self.weekStart = weekStart
        self.absences = absences
        self.seed = seed
    }
}

/// The deterministic greedy planner (ADR 0009; plan section 5).
///
/// Pipeline: date range (R8) -> expand slots -> hard filter -> greedy select in date/slot
/// order with seeded tie-breaks and the variety rule -> servings. Scoring and explanations
/// (plan section 5 steps 4 and 7) are added by T11; until then every safe candidate scores the
/// same, so selection is the seeded tie-break among variety-respecting candidates.
///
/// The output is always a **draft**. `OMPServices` runs `PlanValidator` on it before showing it
/// (AC-4.2); the planner never approves anything.
public enum WeekPlanner {
    /// The variety rule (G5): a recipe is not repeated within any `varietyWindowDays`
    /// consecutive days (so a recipe used on day d is blocked on days d-2 ... d+2, including
    /// another slot on day d).
    public static let varietyWindowDays = 3

    /// Generates a draft week plan.
    ///
    /// Plans only from the clearance snapshot (members, rules, settings), after checking that
    /// the clearance is still valid for `household` at `now` (ADR 0007; T08 review-2).
    ///
    /// - Parameters:
    ///   - clearance: issued by `SafetyGate`.
    ///   - household: the current household, used only to re-check the clearance.
    ///   - library: the recipe library and its tag index.
    ///   - request: plan ids, start date, absences and optional seed.
    ///   - now: the current instant (also the plan's `createdAt`).
    ///   - timeZone: explicit time zone for the gate's day arithmetic.
    /// - Throws: `PlannerError.clearanceNotValid` if `clearance.isValid(for:now:timeZone:)` fails.
    public static func generateWeek(
        clearance: SafetyClearance,
        household: Household,
        library: PlannerLibrary,
        request: WeekPlanRequest,
        now: Date,
        timeZone: TimeZone
    ) throws(PlannerError) -> MealPlan {
        guard clearance.isValid(for: household, now: now, timeZone: timeZone) else {
            throw PlannerError.clearanceNotValid
        }

        let seed =
            request.seed
            ?? PlannerSeed.derived(
                householdID: clearance.householdID, weekStart: request.weekStart, revision: request.revision)
        let slots = SlotExpansion.slots(
            dates: PlanDateRange.dates(from: request.weekStart), members: clearance.members,
            settings: clearance.settings, absences: request.absences)

        var uses: [RecipeID: [LocalDate]] = [:]
        var meals: [PlannedMeal] = []
        for slot in slots {
            let candidates = HardFilter.candidates(for: slot, library: library, clearance: clearance)
            var rng = slotGenerator(seed: seed, date: slot.date, slot: slot.slot)
            let mealID = PlannedMealID(
                request.planId.rawValue + ":" + slot.date.isoString + ":" + slot.slot.rawValue)

            guard let choice = select(from: candidates, on: slot.date, uses: uses, rng: &rng) else {
                meals.append(
                    PlannedMeal(
                        id: mealID, date: slot.date, slot: slot.slot, recipeId: nil, emptyReason: .noSafeRecipe,
                        servings: slot.servings))
                continue
            }
            uses[choice.recipeId, default: []].append(slot.date)
            meals.append(
                PlannedMeal(
                    id: mealID, date: slot.date, slot: slot.slot, recipeId: choice.recipeId,
                    servings: slot.servings, reasons: choice.relaxedVariety ? [.repeatedFewSafeOptions] : []))
        }

        return MealPlan(
            id: request.planId, seriesId: request.seriesId, revision: request.revision, basedOn: request.basedOn,
            weekStart: request.weekStart, status: .draft, meals: meals, contentVersion: library.contentVersion,
            createdAt: now)
    }

    /// A planner choice for one slot.
    struct Choice: Equatable {
        var recipeId: RecipeID
        /// The variety rule had to be relaxed (G5).
        var relaxedVariety: Bool
    }

    /// Greedy selection for one slot (plan section 5 step 5).
    ///
    /// Candidates that respect the variety rule are preferred. Only when none remains is the
    /// rule relaxed: then the candidates whose nearest previous use is furthest away are kept.
    /// Ties are broken by `rng` over the candidates in recipe-id order. `nil` when there is no
    /// candidate at all (the slot stays empty, AC-4.4).
    static func select(
        from candidates: [PlannerLibrary.Entry], on date: LocalDate, uses: [RecipeID: [LocalDate]],
        rng: inout SplitMix64
    ) -> Choice? {
        guard !candidates.isEmpty else { return nil }

        func nearestUse(_ id: RecipeID) -> Int? {
            uses[id]?.map { abs(date.daysSince($0)) }.min()
        }

        let fresh = candidates.filter { entry in
            guard let distance = nearestUse(entry.id) else { return true }
            return distance >= varietyWindowDays
        }
        if !fresh.isEmpty {
            let ids = fresh.map(\.id).sorted()
            return Choice(recipeId: ids[rng.nextIndex(below: ids.count)], relaxedVariety: false)
        }

        // Every candidate was used within the window; all have a nearest use.
        let furthest = candidates.compactMap { nearestUse($0.id) }.max() ?? 0
        let ids = candidates.filter { nearestUse($0.id) == furthest }.map(\.id).sorted()
        return Choice(recipeId: ids[rng.nextIndex(below: ids.count)], relaxedVariety: true)
    }

    /// An independent generator per (date, slot), so one slot's tie-break does not depend on
    /// how many draws earlier slots made.
    static func slotGenerator(seed: PlannerSeed, date: LocalDate, slot: MealSlot) -> SplitMix64 {
        let slotIndex = UInt64(MealSlot.allCases.firstIndex(of: slot) ?? 0)
        let day = UInt64(bitPattern: Int64(date.daysSinceEpoch))
        let key = SplitMix64.mix(day &* 8 &+ slotIndex)
        return SplitMix64(seed: SplitMix64.mix(seed.value ^ key))
    }
}
