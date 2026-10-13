# T10 handoff 1: planner core - safety-critical

- Branch: local `feat/t10` (worktree `../omp-t10`) from `claude/build-v1` @ f7c9882. Not pushed.
- Code commit: 7695d1f. ACs: AC-4.1, AC-4.4, AC-4.6, AC-6.1, AC-6.2, AC-6.3, AC-7.2 (slots), G5. ADR 0009, ADR 0007, plan §5, R7, R8.
- Size: ~1130 lines, ~390 source and ~740 test/fixture. Over the 400-line guideline because the tests are large. I did not split it: the source alone is under 400.

## What (Packages/Core/Sources/OMPDomain)
- `Util/SplitMix64.swift`: seedable `RandomNumberGenerator` (none existed), with `mix(_:)` and `nextIndex(below:)` (rejection sampling, no modulo bias).
- `Planner/PlannerLibrary.swift`: the planner's tag index, built from plain `[Recipe]`/`[Ingredient]` plus `contentVersion` (OMPDomain cannot import OMPRecipes). Contained tags = ingredient `tags ∪ mayContain` over all lines, optional lines included; `declaredTags` is never read. Flags: `hasUnverifiedIngredient` and `hasUnknownIngredient`. Duplicate ids merge conservatively. Entries are sorted by id.
- `Planner/PlanDateRange.swift`: R8 start date and 7 dates.
- `Planner/SlotExpansion.swift`: `MealAbsence`, `PlannerSlot`, `SlotExpansion.slots(dates:members:settings:absences:)`.
  - B/L/D every day. Snack only if `settings.snacksEnabled`.
  - One `lunchbox` slot per day when some member has `needsSchoolLunch` and the weekday is in their `schoolDays`. Only those members eat it.
  - R7: those members are `notEating` at family lunch that day.
  - Absences set `notEating`.
  - Every slot has a serving for every cleared member (default portion; not-eating servings keep their portion, matching the existing fixtures).
  - Fill order within a day: breakfast, lunchbox, lunch, dinner, snack.
- `Planner/HardFilter.swift`: `fits` checks meal type, and a lunchbox slot takes only `lunchboxSuitable` recipes. `isSafe` uses validator semantics: rules = `clearance.rules(covering:)` filtered to hard, for eaters only; tag intersection excludes; unverified + any hard rule on any eater excludes; an unknown ingredient always excludes. `candidates(for:library:clearance:)` is public for T11/T12.
- `Planner/WeekPlanner.swift`: `generateWeek(clearance:household:library:request:now:timeZone:) throws(PlannerError) -> MealPlan`.
  - It first calls `clearance.isValid(for:now:timeZone:)`. If that fails it throws `.clearanceNotValid` (closes the tracked T08 review-2 item for this entry point). It then plans only from the clearance snapshot.
  - `WeekPlanRequest` holds the plan/series ids, revision, basedOn, weekStart, absences and an optional seed. `PlannerSeed.derived(householdID:weekStart:revision:)` uses the first 8 bytes of SHA-256, which is stable across platforms (it does not use `Hasher`).
  - Greedy in slot order. Each (date, slot) gets its own SplitMix64 stream. Ties are broken over candidates in id order.
  - Variety: `varietyWindowDays = 3` means no repeat across any 3 consecutive days (|Δdays| < 3 blocks, same day included). When every safe candidate is blocked, it picks those whose nearest use is furthest away and adds reasons `[.repeatedFewSafeOptions]`.
  - With no candidate the meal is empty with `.noSafeRecipe`. Meal ids are deterministic: `<planId>:<date>:<slot>`.
  - The output is `.draft` with the library's `contentVersion` and `createdAt = now`. There is no scoring or explanations yet (T11): all safe candidates score equally.
- `Package.swift`: the `OMPSafetyCheckTests` target now also depends on `OMPRecipes` (test-only, so it can use the bundled seed). Library dependencies are unchanged.

## Tests
- `Tests/OMPDomainTests/PlannerTests.swift` (+ `PlannerFixture.swift`), covering:
  - clearance: valid, stale (household edited), other household, overdue at day 181;
  - AC-6.1 shape (21 meals, B/L/D order, unique ids), and snacks on;
  - AC-6.2 portions (band and override);
  - AC-7.2/R7 lunchbox days, eaters and lunch exclusion; lunchbox only from suitable recipes over 20 seeds, and empty when none is suitable;
  - AC-6.3 absent member's rule doesn't constrain;
  - R8 dates;
  - hard filter: no rules; unknown ingredient; mayContain on an optional line; declaredTags ignored; unverified with and without a rule-holding eater; household scope; AC-4.1 over 20 seeds;
  - AC-4.4 empty with reason;
  - AC-4.6 determinism (explicit and derived seeds), seeds matter, derived-seed golden (computed with Python hashlib);
  - variety respected over 20 seeds; relaxation with 1 recipe and with 2 alternating;
  - SplitMix64 reference vectors (checked with Python) and `nextIndex` range.
- `Tests/OMPSafetyCheckTests/PlannerValidatorAgreementTests.swift`: every generated plan passes `PlanValidator`. Cases:
  - bundled seed × every catalog restriction × {child, adult, household} scope × 3 seeds, plus the no-rules household;
  - a tricky fixture library (optional mayContain, unverified, unknown ingredient, multi-meal-type recipes) × 8 tag sets × 2 scopes × 5 seeds with absences, plus a non-vacuity check.

## Verification
- `bash scripts/check-core.sh --lint-only`: OK.
- No Swift toolchain here, so nothing was compiled or run. CI (Linux + macOS) is the verification of record. I checked the signatures against the sources by hand.

## Decisions / questions for reviewer
1. **R8 clamp (deviation to confirm):** `PlanDateRange.startDate` returns `max(previousEnd + 1, today)` so a plan never starts in the past. R8 literally says "the day after the previous one ends". Recommend keeping the clamp.
2. **Variety window reading:** "no repeat within 3 days" is read as "no two uses less than 3 days apart" (this includes two slots on the same day). Alternative: block only `d+1...d+3`.
3. **Unknown-ingredient recipes** are excluded even for slots with no eaters, which is stricter than the validator (it reports nothing when there are no eaters). Fail closed.
4. **Slot existence vs eaters:**
   - A slot whose members are all absent is still planned. With no eaters there are no constraints, which matches the validator.
   - A lunchbox slot exists whenever someone needs a lunchbox that day, even if every lunchbox member is marked absent.
5. `reasons` is empty for normal picks; T11 adds the top-two explanations.
6. The lunchbox rule uses `needsSchoolLunch`, not `label.role == .child`.
