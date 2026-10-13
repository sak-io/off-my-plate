import Foundation

/// Why the planner refused to plan (ADR 0007).
public enum PlannerError: Error, Sendable, Hashable {
    /// The clearance does not match the household any more, or the safety gate no longer passes
    /// at `now` (for example a re-confirmation fell due). Run the gate again.
    case clearanceNotValid
    /// The plan has no meal with this id.
    case mealNotFound(PlannedMealID)
    /// The meal is locked; locked meals never change (AC-8.3). Unlock it first.
    case mealLocked(PlannedMealID)
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
        hashed(householdID.rawValue + "|" + weekStart.isoString + "|" + String(revision))
    }

    /// A seed from the first 8 bytes (big-endian) of SHA-256 of `text`.
    static func hashed(_ text: String) -> PlannerSeed {
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
/// order: the variety rule filters, `PlannerScoring` ranks, seeded tie-breaks decide among equal
/// scores -> servings -> explanations (top two positive score components). Soft signals
/// (pantry, Facts, cook log) only ever rank candidates the hard filter already allowed (AC-12.6).
///
/// Editing entry points (`alternatives`, `reroll`, `regenerate`) are in `WeekPlanner+Editing`.
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
    ///   - signals: pantry, Facts and cook log for scoring; they never affect safety.
    ///   - now: the current instant (also the plan's `createdAt`).
    ///   - timeZone: explicit time zone for the gate's day arithmetic.
    /// - Throws: `PlannerError.clearanceNotValid` if `clearance.isValid(for:now:timeZone:)` fails.
    public static func generateWeek(
        clearance: SafetyClearance,
        household: Household,
        library: PlannerLibrary,
        request: WeekPlanRequest,
        signals: PlannerSignals = PlannerSignals(),
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
        let context = PlannerScoring.Context(signals: signals, now: now, timeZone: timeZone)

        var uses: [RecipeID: [LocalDate]] = [:]
        var meals: [PlannedMeal] = []
        for slot in slots {
            let candidates = HardFilter.candidates(for: slot, library: library, clearance: clearance)
            var rng = slotGenerator(seed: seed, date: slot.date, slot: slot.slot)
            let mealID = PlannedMealID(
                request.planId.rawValue + ":" + slot.date.isoString + ":" + slot.slot.rawValue)

            let target = Target(date: slot.date, slot: slot.slot, eaterIDs: slot.eaterIDs)
            guard let choice = select(from: candidates, for: target, uses: uses, context: context, rng: &rng) else {
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
                    servings: slot.servings, reasons: choice.reasons))
        }

        return MealPlan(
            id: request.planId, seriesId: request.seriesId, revision: request.revision, basedOn: request.basedOn,
            weekStart: request.weekStart, status: .draft, meals: meals, contentVersion: library.contentVersion,
            createdAt: now)
    }

    /// One meal to fill: its day, slot and eaters.
    struct Target: Equatable {
        var date: LocalDate
        var slot: MealSlot
        var eaterIDs: [MemberID]
    }

    /// A planner choice for one slot.
    struct Choice: Equatable {
        var recipeId: RecipeID
        /// The variety rule had to be relaxed (G5).
        var relaxedVariety: Bool
        /// The explanation to store on the meal (AC-4.7).
        var reasons: [ExplanationReason]
    }

    /// Whether `reason` is a zero-point filler rather than a score component.
    static func isFiller(_ reason: ExplanationReason) -> Bool {
        reason == .goodForLunchboxes || reason == .differentFromYesterday
    }

    /// The explanation for a choice: the score's reasons, or, when variety was relaxed, the
    /// relaxation note plus the best real score reason.
    static func reasons(_ breakdown: PlannerScoring.Breakdown, relaxedVariety: Bool) -> [ExplanationReason] {
        guard relaxedVariety else { return breakdown.reasons }
        var result: [ExplanationReason] = [.repeatedFewSafeOptions]
        result.append(contentsOf: breakdown.reasons.filter { !isFiller($0) }.prefix(1))
        return result
    }

    /// The day distance from `date` to the nearest other use of `id`, or `nil` if unused.
    static func nearestUse(_ id: RecipeID, to date: LocalDate, uses: [RecipeID: [LocalDate]]) -> Int? {
        uses[id]?.map { abs(date.daysSince($0)) }.min()
    }

    /// Greedy selection for one slot (plan section 5 step 5).
    ///
    /// Candidates that respect the variety rule are preferred. Only when none remains is the
    /// rule relaxed: then the candidates whose nearest previous use is furthest away are kept.
    /// Among those, the highest score plus `adjustment` wins; ties are broken by `rng` over the
    /// tied candidates in recipe-id order. `nil` when there is no candidate at all (the slot
    /// stays empty, AC-4.4).
    static func select(
        from candidates: [PlannerLibrary.Entry], for target: Target, uses: [RecipeID: [LocalDate]],
        context: PlannerScoring.Context, adjustment: (PlannerLibrary.Entry) -> Int = { _ in 0 },
        rng: inout SplitMix64
    ) -> Choice? {
        guard !candidates.isEmpty else { return nil }

        var pool = candidates.filter { entry in
            guard let distance = nearestUse(entry.id, to: target.date, uses: uses) else { return true }
            return distance >= varietyWindowDays
        }
        let relaxed = pool.isEmpty
        if relaxed {
            // Every candidate was used within the window, so every one has a nearest use.
            let distances = candidates.compactMap { nearestUse($0.id, to: target.date, uses: uses) }
            precondition(distances.count == candidates.count, "relaxed variety needs a use for every candidate")
            guard let furthest = distances.max() else {
                preconditionFailure("candidates is not empty")
            }
            pool = candidates.filter { nearestUse($0.id, to: target.date, uses: uses) == furthest }
        }

        typealias Scored = (entry: PlannerLibrary.Entry, breakdown: PlannerScoring.Breakdown, rank: Int)
        let scored = pool.map { entry -> Scored in
            let breakdown = PlannerScoring.score(
                entry, date: target.date, slot: target.slot, eaterIDs: target.eaterIDs, plannedUses: uses,
                context: context)
            return (entry: entry, breakdown: breakdown, rank: breakdown.total + adjustment(entry))
        }
        guard let best = scored.map({ $0.rank }).max() else {
            preconditionFailure("the pool is not empty")
        }
        let tied = scored.filter { $0.rank == best }.sorted { $0.entry.id < $1.entry.id }
        let pick = tied[rng.nextIndex(below: tied.count)]
        return Choice(
            recipeId: pick.entry.id, relaxedVariety: relaxed,
            reasons: reasons(pick.breakdown, relaxedVariety: relaxed))
    }

    /// An independent generator per (date, slot), so one slot's tie-break does not depend on
    /// how many draws earlier slots made.
    static func slotGenerator(seed: PlannerSeed, date: LocalDate, slot: MealSlot) -> SplitMix64 {
        guard let index = MealSlot.allCases.firstIndex(of: slot) else {
            preconditionFailure("every MealSlot is in allCases")
        }
        let slotIndex = UInt64(index)
        let day = UInt64(bitPattern: Int64(date.daysSinceEpoch))
        let key = SplitMix64.mix(day &* 8 &+ slotIndex)
        return SplitMix64(seed: SplitMix64.mix(seed.value ^ key))
    }
}
