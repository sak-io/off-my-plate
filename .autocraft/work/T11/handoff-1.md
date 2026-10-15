# T11 handoff 1: planner scoring, explanations, swap/re-roll/regenerate (safety-critical: calls the planner)

- Branch: local `feat/t11` (worktree `../omp-t11`) from `claude/build-v1` @ e790125. Not pushed.
- Code commit: ae5dc3f. ACs: AC-4.7, AC-8.1, AC-8.2, AC-8.3, AC-12.6 (plus AC-4.6 determinism kept). Plan §5 steps 4, 5, 7 and entry points; UX U7 / S-12; tracked item "T10 review-1 WeekPlanner `?? 0`".
- Size: ~1500 lines, ~720 source and ~830 test. Over the 400-line guideline. Not split, because the editing entry points share the scorer and the agreement test needs both.

## What (Packages/Core/Sources/OMPDomain/Planner)
- `PlannerScoring.swift` (new):
  - `PlannerSignals` holds the pantry, Facts and cook log.
  - `ScoreComponent` enum.
  - `PlannerScoring.Context(signals:now:timeZone:)` precomputes the signals.
  - `PlannerScoring.score(_:date:slot:eaterIDs:plannedUses:context:) -> Breakdown` returns `points` per component, `total` and the top-two `reasons`.
  - Points are integer hundredths of the plan weights, so ties are exact on every platform.
  - Weights: pantryCoverage 300 × covered/required, expirySoon 200, cuisineAffinity 200 × confidence, favourite 100, dislikeRecipe −400, dislikeIngredient −200 per distinct ingredient, timeFit 100 (weekday Mon–Fri dinner ≤ 40 min), recentlyCooked −200 (cooked 0–7 days before the meal date), sameDayDuplicate −300.
  - The pantry counts only items that are resolved, quantified, not expired and **confident**, and only if the item is still in date on the meal date. "Expiry soon" means the best-before date is ≤ 3 days from today and still in date for the meal, so the greedy order puts the meal on an early day.
  - **AC-12.6**: a Fact is used only if `status == .active` and its origin is `.stated` or `.confirmed`. Inferred and default Facts never score. Confidence is clamped to 0...1, and NaN counts as 0. Member Facts apply only when that member is eating. Facts are not passed to `HardFilter` at all.
  - Explanations are the positive components sorted by points. Ties follow this order: expiry, coverage, cuisine, favourite, timeFit. The expiring ingredient is named once.
  - Zero-point fillers (`.goodForLunchboxes` for a lunchbox slot, `.differentFromYesterday` when the recipe was not planned or cooked the day before) top the list up to 2, so every planned meal has an explanation (AC-4.7).
- `PlannerLibrary.Entry` now also has `region`, `totalMinutes` and `requiredIngredients` (non-optional lines, in line order). These are used for scoring only, never for safety. When a recipe id appears twice, the first region is kept, the larger time is used and the ingredients are unioned.
- `WeekPlanner.swift`:
  - `generateWeek` takes `signals: PlannerSignals = PlannerSignals()`, so existing callers still compile.
  - `select` applies the variety filter first, then the highest score plus an adjustment, then the seeded rng among tied ids.
  - When variety is relaxed, the reasons are `[.repeatedFewSafeOptions, <best real reason>]`.
  - Tracked item: both unreachable `?? 0` fallbacks (in the relaxed-variety max and `slotGenerator`) are now explicit `precondition`/`preconditionFailure`.
  - `PlannerError` has new cases `.mealNotFound(id)` and `.mealLocked(id)`.
  - `PlannerSeed.hashed(_:)` is internal and is shared by all derived seeds. The existing golden test is unchanged.
- `HardFilter.candidates(for: MealSlot, eaterIDs:library:clearance:)` overload.
- `WeekPlanner+Editing.swift` (new). Every entry point calls `clearance.isValid(for:now:timeZone:)` first. Recipes come only from `HardFilter.candidates` for the meal's eaters. The eaters are computed fail-closed with the same semantics as `PlanValidator`: serving members plus all cleared members, minus members whose only servings are `notEating`.
  - `alternatives(for:in:reason:excluding:limit: = 3, ...) -> [MealAlternative]`.
    - Never returns the current recipe or anything in `excluding`.
    - Order: variety-respecting options first, then repeats (furthest previous use first, with `.repeatedFewSafeOptions`), then by rank, then by id.
    - A negative `limit` is treated as 0.
    - Throws `.mealLocked` for a locked meal.
  - `reroll(_:in:reason:excluding:..., seed:) -> PlannedMeal?` ("Pick for me").
    - Uses the same ranking, with a seeded tie-break among the top-tied options.
    - Returns `nil` only when no other safe recipe exists (C-067).
    - Never returns the current recipe.
    - Logging the learning event is left to the caller (OMPServices).
  - `regenerate(_:keepingLocked: = true, ..., seed:) -> [PlannedMeal]` returns the same ids in the same order, ready for `PlanLifecycle.edit`. Kept unchanged:
    - cooked meals;
    - meals dated before today (plan §5 step 0);
    - locked meals that are still safe.
    - Every other meal is replanned in date/fill order, counting kept meals for variety.
  - `PlannedMeal.replacingRecipe(with:)`, for applying a swap.

## Assumptions / questions (recommended default in bold)
1. **Reroll reasons**:
   - `.tooLong` keeps only strictly shorter recipes. If there are none, it falls back to all other safe recipes.
   - `.dontFeelLikeIt` subtracts 100 for each required ingredient shared with the rejected recipe.
   - `.kidsWontEatIt` does the same and adds 100 if the recipe is `lunchboxSuitable`. This is the only signal for child-friendly food; the library has no other.
   - These adjustments rank options and are never shown. The same reason chip also shapes the 3 alternatives (U7 shares one sheet). **Keep.**
2. **Locked but now unsafe** (a rule was added after locking): regenerate replans and unlocks that meal (safety over lock). Otherwise the validator would empty it anyway. Alternative: keep it and leave it to R1 `blockedBySafety`. **Replan.**
3. **Regenerate novelty**:
   - The meal's current recipe gets −100, so regenerating a pantry-dominated week still changes something.
   - The default seed comes from the household, the plan id and the plan's content hash, so each regenerate is deterministic but different.
   - Replanned meals are unlocked, including when `keepingLocked: false`.
4. `prefersQuickWeekday` Fact: +100 more on timeFit. This is not in the plan's weight list, but without it the Fact would have no effect. **Keep.**
5. "Same-day duplicate main −3" is implemented as the same recipe on the same day, because `Recipe` has no main/course field. The variety rule already blocks this unless variety is relaxed. A course field would be a T04/content change.
6. Pantry quantities are not consumed by earlier picks, so the same rice can "cover" several meals. Proper requirement arithmetic stays in the shopping list (plan §6).
7. Members added after the plan get no new `MealServing` on regenerate. They are still treated as eaters for safety (fail closed). Adding servings is left to the services that edit "who's eating".

## Tests
- `PlannerScoringTests.swift`:
  - each component tested in isolation, including:
    - its threshold boundaries (40 min, 3-day expiry, day 7 vs 8);
    - unusable pantry items (low confidence, expired, zero, free text) and optional lines;
    - Fact origin and status filtering (AC-12.6), NaN confidence, member vs household Facts;
  - explanation ordering, tie order, the expiring ingredient named once, fillers, every meal explained;
  - signals in a full week: pantry/expiry pull a recipe forward; a disliked recipe is avoided but still used when it is the only safe one;
  - AC-12.6: with maximal Facts and pantry pointing at unsafe recipes, every meal is still from the hard-filter set, and empty slots are identical with and without Facts;
  - determinism with signals;
  - performance budget: 200 recipes, snacks + lunchbox, signals, < 200 ms after a warm-up.
- `PlannerEditingTests.swift`:
  - alternatives:
    - at most 3, safe, ranked, `limit` 0 and negative;
    - explanations and `replacingRecipe`;
    - variety-respecting options first, repeats last with the relaxation reason;
    - a cleared member missing from servings is treated as an eater; a `notEating` member is not;
    - refusals: stale clearance, unknown meal, locked meal;
  - reroll:
    - never the current recipe (20 seeds); `nil` only when nothing else is safe; an empty meal;
    - `excluding`;
    - each reason: tooLong beats a higher-scoring longer recipe, plus the fallback; dontFeelLikeIt; kidsWontEatIt (10 seeds each);
    - determinism; locked and overdue-clearance refusals;
  - regenerate:
    - locked meals unchanged and ids/order kept, all others safe (5 seeds);
    - `keepingLocked: false`;
    - a locked meal that became unsafe is replanned;
    - past and cooked meals are kept;
    - variety holds around kept meals;
    - determinism; stale clearance is refused.
- `PlannerTests.swift`: the three variety tests now check `.repeatedFewSafeOptions` presence and position instead of `reasons == []`.
- `PlannerValidatorAgreementTests.swift`: new cases run every T11 path with maximal signals (all recipes favourite, all cuisines liked, every ingredient in the pantry and expiring) through `PlanValidator`. The paths are: the scored week, every meal swapped to every alternative, every meal re-rolled with each reason (and with none), and regenerate with every third meal locked. Coverage:
  - the bundled seed × every restriction × {child, household};
  - the tricky library × 6 tag sets × 2 scopes × 3 seeds.

## Verification
- `bash scripts/check-core.sh --lint-only`: OK.
- No Swift toolchain here, so nothing was compiled or run. CI (Linux + macOS) is the verification of record.
- I hand-checked:
  - typed throws;
  - closure return annotations on multi-statement closures;
  - no tuple key paths;
  - no trailing closures in `guard` conditions;
  - `Sendable` on the new public types;
  - no locale APIs (pure `LocalDate` arithmetic; `ContinuousClock` in tests only, macOS 15 / iOS 18 platform floor).
- The performance test is the most timing-sensitive test on CI debug builds. If it flakes, look at `Context.facts(for:)` (it allocates per score call) before raising the budget.
