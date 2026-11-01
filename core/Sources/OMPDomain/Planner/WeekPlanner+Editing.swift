import Foundation

/// A swap option for one meal (AC-8.1): a recipe that passed the hard filter for the meal's
/// eaters, with its explanation.
public struct MealAlternative: Sendable, Hashable {
    public let recipeId: RecipeID
    public let reasons: [ExplanationReason]

    public init(recipeId: RecipeID, reasons: [ExplanationReason]) {
        self.recipeId = recipeId
        self.reasons = reasons
    }
}

extension PlannedMeal {
    /// This meal with `alternative`'s recipe (a swap or re-roll). The id, day, slot, servings,
    /// lock and cook link are kept; the safety block is cleared because the recipe changed
    /// (`OMPServices` re-validates the plan before showing it, AC-4.2).
    ///
    /// `package` access (T12 review): it clears the safety block without a clearance, so only
    /// Core code that re-validates the resulting plan with `PlanValidator` before saving or
    /// approving it may call it; the app and the Apple package cannot.
    package func replacingRecipe(with alternative: MealAlternative) -> PlannedMeal {
        var meal = self
        meal.recipeId = alternative.recipeId
        meal.emptyReason = nil
        meal.reasons = alternative.reasons
        meal.blockedBySafety = false
        return meal
    }
}

/// Swap, re-roll and regenerate (plan section 5 entry points; AC-8.1, AC-8.2, AC-8.3).
///
/// Every entry point re-checks the clearance first and only ever offers recipes from the hard
/// filter for the meal's eaters. The eaters of an existing meal are computed fail closed, like
/// `PlanValidator`: every serving's member and every cleared member, minus members whose only
/// servings are `notEating`. Results are drafts; `OMPServices` validates them (AC-4.2) and applies
/// them through `PlanLifecycle.edit` (AC-8.4).
extension WeekPlanner {
    /// Rank adjustment per required ingredient shared with the rejected recipe, for the
    /// "don't feel like it" and "kids won't eat it" reasons (ASSUMPTION, T11 handoff).
    public static let rerollSharedIngredientPenalty = -100
    /// Rank bonus for lunchbox-suitable recipes on "kids won't eat it" (ASSUMPTION: lunchbox
    /// suitability is the only child-friendliness signal the library has).
    public static let kidsLunchboxBonus = 100
    /// Rank adjustment for keeping a meal's current recipe on regenerate, so regenerating can
    /// change a week whose scores are dominated by one recipe (ASSUMPTION, T11 handoff).
    public static let regenerateRepeatPenalty = -100

    /// Up to `limit` (default 3) alternatives for a meal, best first (AC-8.1; UX U7).
    ///
    /// Never the current recipe or one in `excluding`. Candidates that respect the variety rule
    /// come first; others follow only when too few remain (with `.repeatedFewSafeOptions`).
    /// An optional `reason` shapes the list as for `reroll`. Empty when nothing else is safe.
    ///
    /// - Throws: `.clearanceNotValid`, `.mealNotFound`, or `.mealLocked` (AC-8.3).
    public static func alternatives(
        for mealID: PlannedMealID,
        in plan: MealPlan,
        reason: RerollReason? = nil,
        excluding: Set<RecipeID> = [],
        limit: Int = 3,
        clearance: SafetyClearance,
        household: Household,
        library: PlannerLibrary,
        signals: PlannerSignals = PlannerSignals(),
        now: Date,
        timeZone: TimeZone
    ) throws(PlannerError) -> [MealAlternative] {
        guard clearance.isValid(for: household, now: now, timeZone: timeZone) else {
            throw PlannerError.clearanceNotValid
        }
        let meal = try editableMeal(mealID, in: plan)
        let context = PlannerScoring.Context(signals: signals, now: now, timeZone: timeZone)
        return options(
            for: meal, in: plan, reason: reason, excluding: excluding, clearance: clearance, library: library,
            context: context
        )
        .prefix(max(0, limit))
        .map { MealAlternative(recipeId: $0.recipeId, reasons: $0.reasons) }
    }

    /// "Pick for me" (AC-8.2; UX U7): the meal with a different safe recipe, or `nil` when no
    /// other safe recipe exists (UI copy C-067). Never the current recipe or one in `excluding`.
    ///
    /// Reasons: `.tooLong` keeps only shorter recipes when there are any; `.dontFeelLikeIt` and
    /// `.kidsWontEatIt` rank down recipes sharing required ingredients with the current one, and
    /// `.kidsWontEatIt` ranks up lunchbox-suitable recipes. The best-ranked option wins; ties go
    /// through a SplitMix64 seeded from `seed` (default: derived from the plan, meal, current
    /// recipe and `excluding`). Logging the reason as a learning event is the caller's job.
    ///
    /// - Throws: `.clearanceNotValid`, `.mealNotFound`, or `.mealLocked` (AC-8.3).
    public static func reroll(
        _ mealID: PlannedMealID,
        in plan: MealPlan,
        reason: RerollReason?,
        excluding: Set<RecipeID> = [],
        clearance: SafetyClearance,
        household: Household,
        library: PlannerLibrary,
        signals: PlannerSignals = PlannerSignals(),
        seed: PlannerSeed? = nil,
        now: Date,
        timeZone: TimeZone
    ) throws(PlannerError) -> PlannedMeal? {
        guard clearance.isValid(for: household, now: now, timeZone: timeZone) else {
            throw PlannerError.clearanceNotValid
        }
        let meal = try editableMeal(mealID, in: plan)
        let context = PlannerScoring.Context(signals: signals, now: now, timeZone: timeZone)
        let ranked = options(
            for: meal, in: plan, reason: reason, excluding: excluding, clearance: clearance, library: library,
            context: context)
        guard let first = ranked.first else { return nil }
        let tied = ranked.prefix { $0.sortKey == first.sortKey }

        let excluded: [String] = excluding.map(\.rawValue).sorted()
        let seedParts: [String] = [
            "reroll", clearance.householdID.rawValue, plan.id.rawValue, meal.id.rawValue,
            meal.recipeId?.rawValue ?? "", excluded.joined(separator: ","),
        ]
        let seedText = seedParts.joined(separator: "|")
        var rng = SplitMix64(seed: (seed ?? PlannerSeed.hashed(seedText)).value)
        let pick = tied[tied.startIndex + rng.nextIndex(below: tied.count)]
        return meal.replacingRecipe(with: MealAlternative(recipeId: pick.recipeId, reasons: pick.reasons))
    }

    /// Regenerates the week (AC-8.3) and returns the new meals in the plan's order with their ids.
    ///
    /// Kept unchanged: meals already cooked, meals on days before today (plan section 5 step 0),
    /// and, when `keepingLocked`, locked meals that are still safe under the clearance. A locked
    /// meal that is no longer safe is replanned, unlocked, and gets `.lockedMealNoLongerSafe` as
    /// its first reason (safety over lock; T11 review-1). Every other meal is replanned with the same eaters, variety rule and scoring as
    /// `generateWeek`, counting kept meals for variety; replanned meals are unlocked.
    ///
    /// - Parameter seed: default: derived from the household, the plan id and its content hash,
    ///   so each regenerate of a changed plan breaks ties differently, but the same plan always
    ///   regenerates the same way (AC-4.6).
    /// - Throws: `.clearanceNotValid`.
    public static func regenerate(
        _ plan: MealPlan,
        keepingLocked: Bool = true,
        clearance: SafetyClearance,
        household: Household,
        library: PlannerLibrary,
        signals: PlannerSignals = PlannerSignals(),
        seed: PlannerSeed? = nil,
        now: Date,
        timeZone: TimeZone
    ) throws(PlannerError) -> [PlannedMeal] {
        guard clearance.isValid(for: household, now: now, timeZone: timeZone) else {
            throw PlannerError.clearanceNotValid
        }
        let context = PlannerScoring.Context(signals: signals, now: now, timeZone: timeZone)
        let seedParts: [String] = ["regenerate", clearance.householdID.rawValue, plan.id.rawValue, plan.contentHash]
        let seed = seed ?? PlannerSeed.hashed(seedParts.joined(separator: "|"))

        func keeps(_ meal: PlannedMeal) -> Bool {
            if meal.cooked != nil || meal.date < context.today {
                return true
            }
            guard keepingLocked, meal.locked else { return false }
            guard let recipeId = meal.recipeId else { return true }
            guard let entry = library.entry(recipeId) else { return false }
            return HardFilter.isSafe(entry, eaterIDs: eaterIDs(of: meal, clearance: clearance), clearance: clearance)
        }

        var meals = plan.meals
        var uses: [RecipeID: [LocalDate]] = [:]
        var replan: [Int] = []
        for (index, meal) in meals.enumerated() {
            if keeps(meal) {
                if let recipeId = meal.recipeId {
                    uses[recipeId, default: []].append(meal.date)
                }
            } else {
                replan.append(index)
            }
        }
        // Fill in date order, then `SlotExpansion.fillOrder`, as `generateWeek` does.
        func fillRank(_ slot: MealSlot) -> Int {
            SlotExpansion.fillOrder.firstIndex(of: slot) ?? SlotExpansion.fillOrder.count
        }
        replan.sort { lhs, rhs in
            let a = meals[lhs]
            let b = meals[rhs]
            if a.date != b.date { return a.date < b.date }
            if a.slot != b.slot { return fillRank(a.slot) < fillRank(b.slot) }
            return lhs < rhs
        }

        for index in replan {
            let meal = meals[index]
            let eaters = eaterIDs(of: meal, clearance: clearance)
            let candidates = HardFilter.candidates(
                for: meal.slot, eaterIDs: eaters, library: library, clearance: clearance)
            var rng = slotGenerator(seed: seed, date: meal.date, slot: meal.slot)
            let target = Target(date: meal.date, slot: meal.slot, eaterIDs: eaters)
            let current = meal.recipeId
            // Not kept although locked (and not cooked or past): its recipe is no longer safe.
            let lockNoLongerSafe = keepingLocked && meal.locked
            let choice = select(
                from: candidates, for: target, uses: uses, context: context,
                adjustment: { $0.id == current ? regenerateRepeatPenalty : 0 }, rng: &rng)

            var updated = meal
            updated.locked = false
            updated.blockedBySafety = false
            updated.recipeId = choice?.recipeId
            updated.emptyReason = choice == nil ? .noSafeRecipe : nil
            updated.reasons = choice?.reasons ?? []
            if lockNoLongerSafe {
                // Surface the change to the UI first; keep at most one score reason (two in total).
                var reasons: [ExplanationReason] = [.lockedMealNoLongerSafe]
                reasons.append(contentsOf: updated.reasons.prefix(1))
                updated.reasons = reasons
            }
            if let choice {
                uses[choice.recipeId, default: []].append(meal.date)
            }
            meals[index] = updated
        }
        return meals
    }

    // MARK: Helpers

    /// The meal with `id`, if it exists and is not locked.
    static func editableMeal(_ id: PlannedMealID, in plan: MealPlan) throws(PlannerError) -> PlannedMeal {
        guard let meal = plan.meal(id) else {
            throw PlannerError.mealNotFound(id)
        }
        guard !meal.locked else {
            throw PlannerError.mealLocked(id)
        }
        return meal
    }

    /// Who eats an existing meal, fail closed (the same semantics as `PlanValidator`): serving
    /// members, then the remaining cleared members, minus members whose only servings are
    /// `notEating` (AC-6.3). A cleared member missing from `servings` is treated as eating.
    static func eaterIDs(of meal: PlannedMeal, clearance: SafetyClearance) -> [MemberID] {
        var eating = Set<MemberID>()
        var notEating = Set<MemberID>()
        for serving in meal.servings {
            if serving.notEating {
                notEating.insert(serving.memberId)
            } else {
                eating.insert(serving.memberId)
            }
        }
        let optedOut = notEating.subtracting(eating)
        var eaters: [MemberID] = []
        var seen = Set<MemberID>()
        for id in meal.servings.map(\.memberId) + clearance.members.map(\.id)
        where !optedOut.contains(id) && seen.insert(id).inserted {
            eaters.append(id)
        }
        return eaters
    }

    /// A ranked swap/re-roll option.
    struct Option {
        /// Sort key: variety-respecting first; then (relaxed only) the furthest other use; then
        /// the higher rank. Options with equal keys are tied.
        struct SortKey: Equatable {
            var fresh: Bool
            var distance: Int
            var rank: Int
        }

        var recipeId: RecipeID
        var reasons: [ExplanationReason]
        var sortKey: SortKey
    }

    /// Every safe option for `meal` other than its current recipe and `excluding`, best first,
    /// ties in recipe-id order.
    static func options(
        for meal: PlannedMeal, in plan: MealPlan, reason: RerollReason?, excluding: Set<RecipeID>,
        clearance: SafetyClearance, library: PlannerLibrary, context: PlannerScoring.Context
    ) -> [Option] {
        let eaters = eaterIDs(of: meal, clearance: clearance)
        var uses: [RecipeID: [LocalDate]] = [:]
        for other in plan.meals where other.id != meal.id {
            if let recipeId = other.recipeId {
                uses[recipeId, default: []].append(other.date)
            }
        }

        var excluded = excluding
        if let current = meal.recipeId {
            excluded.insert(current)
        }
        var candidates = HardFilter.candidates(
            for: meal.slot, eaterIDs: eaters, library: library, clearance: clearance
        )
        .filter { !excluded.contains($0.id) }

        let current = meal.recipeId.flatMap { library.entry($0) }
        if reason == .tooLong, let current {
            let shorter = candidates.filter { $0.totalMinutes < current.totalMinutes }
            if !shorter.isEmpty {
                candidates = shorter
            }
        }
        func adjustment(_ entry: PlannerLibrary.Entry) -> Int {
            guard let current else { return 0 }
            let shared = entry.requiredIngredients.filter { current.requiredIngredients.contains($0) }.count
            switch reason {
            case .some(.dontFeelLikeIt):
                return rerollSharedIngredientPenalty * shared
            case .some(.kidsWontEatIt):
                return rerollSharedIngredientPenalty * shared + (entry.lunchboxSuitable ? kidsLunchboxBonus : 0)
            case .some(.tooLong), .none:
                return 0
            }
        }

        let options = candidates.map { entry -> Option in
            let distance = nearestUse(entry.id, to: meal.date, uses: uses)
            let fresh = distance.map { $0 >= varietyWindowDays } ?? true
            let breakdown = PlannerScoring.score(
                entry, date: meal.date, slot: meal.slot, eaterIDs: eaters, plannedUses: uses, context: context)
            return Option(
                recipeId: entry.id, reasons: reasons(breakdown, relaxedVariety: !fresh),
                sortKey: Option.SortKey(
                    fresh: fresh, distance: fresh ? 0 : (distance ?? 0), rank: breakdown.total + adjustment(entry)))
        }
        // `candidates` is in id order and the sort is stable, so ties stay in id order.
        return options.enumerated()
            .sorted { lhs, rhs in
                let a = lhs.element.sortKey
                let b = rhs.element.sortKey
                if a.fresh != b.fresh { return a.fresh }
                if a.distance != b.distance { return a.distance > b.distance }
                if a.rank != b.rank { return a.rank > b.rank }
                return lhs.offset < rhs.offset
            }
            .map { $0.element }
    }
}
