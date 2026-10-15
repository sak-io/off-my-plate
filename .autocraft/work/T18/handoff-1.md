# T18 Services A (household, safety, planning, approval, lunchbox): developer handoff 1

```
HANDOFF
From: developer            To: pr-reviewer
Status: DONE (safety-critical: full review)
Summary: HouseholdService, SafetyService (R1), PlanService (generate/regenerate/reroll/
  alternatives/swap/lock/discard/approve, working vs active approved plan, pending diff),
  LunchboxService (U11 answers, AC-7.2 setup), shared PlanningEngine + ServiceContext.
  NOT compiled locally (no Swift toolchain); lints pass (scripts/check-core.sh --lint-only).
  Linux CI is the first compile.
Artifacts: local branch feat/t18 (worktree ../omp-t18), 2 commits; files below.
Open items: 1. CI compile/test. 2. Deviations D1-D6 need reviewer agreement.
Next: fresh-context review; team lead merges feat/t18 once Linux CI is green (Core-only).
```

## Sources traced
tasks.md T18; plan.md R1/V1, 4.2, 5 (R8, "OMPServices then runs PlanValidator"), 12a #1/#3;
spec AC-1.2, 1.4, 1.5, 3.1-3.3, 3.5, 4.2, 5.1-5.7, 7.1-7.3, 8.1-8.4; flows.md U4, U11;
tracked.md items for T18 (T13 review-1, T10 review-1, TR-2); T12-review note on `replacingRecipe`.

## Files
- `Sources/OMPServices/ServiceContext.swift`: `PlanningLibrary` (planner index + independent
  `SafetyCheckLibrary` + catalog restrictions + contentVersion), `ServiceError`,
  `ServiceDiagnostic`, `ServiceContext` (repos, clock, library, id factory, diagnostics hook),
  FIFO `ServiceLock` actor, `mappingDomainErrors`.
- `Sources/OMPServices/PlanningEngine.swift` (internal): gate -> fresh clearance, signals,
  working-plan resolution, `sanitizedDraft` (validate, empty validator-rejected meals with
  `.removedByValidator` + diagnostic, re-validate, set flags), `replanMeals` (reroll; safety
  beats lock), `fixedDraft`, `recheckOpenPlans` (R1). Public `ValidatedPlan`, `SafetyRecheckOutcome`.
- `Sources/OMPServices/{Household,Safety,Plan,Lunchbox}Service.swift`.
- `Sources/OMPDomain/Planner/WeekPlanner+Editing.swift`: `replacingRecipe` is now `package`.
- `Package.swift`: OMPServicesTests also depends on OMPSafetyCheck and OMPRecipes.
- Tests: `Tests/OMPServicesTests/{ServicesFixture,OnboardingFlowTests,SafetyRecheckTests,
  PlanServiceTests,LunchboxServiceTests}.swift` (in-memory repos, test clock, deterministic ids).

## Tracked items honoured
- Validator at call time, never from the caller: `approve` re-reads the household and runs
  `PlanValidator` under the lock; no public API accepts a `ValidationReport` or `SafetyClearance`.
  Test: rule added behind the services' back -> `approve` fails `.validationFailed`.
- Rule change vs approve interleaving: every mutating use case runs under one FIFO lock
  (validate and save cannot interleave with a rule change). Test: concurrent approve + addRule
  never leaves an unsafe unblocked approved meal.
- R1 after any safety change: open draft AND active approved plan re-validated; approved unsafe
  meals flagged `blockedBySafety` (still approved, off `shoppingMeals`); fixed draft revision
  proposed (or the open revision fixed). With the gate refused: flagged only, `planningRefusal` set.
- Seed `contentVersion` change: `SafetyService.recheckIfLibraryChanged()` runs R1 and stamps the
  new version on re-checked plans (second call returns nil). Test with urad mayContain peanut.
- Atomic approve: `mealPlans.save([approved, superseded])`; R1 saves all changed plans in one call.
- Clamped start: `generateWeek` uses `PlanDateRange.startDate(previousEnd:today:)`
  (previousEnd = max endDate of effectively approved plans).
- `replacingRecipe` (T12 review note): made `package`; the only service callers are `swap`
  (result goes through `sanitizedDraft`/PlanValidator before saving) and the alternatives
  filter (trial plan validated, never saved). All other callers are Core tests.

## Deviations / assumptions (please agree or push back)
- D1 Lock/unlock needs the gate only when it creates a revision of an approved plan (AC-3.3);
  on a draft it doesn't (the plan diagram says "clearance where planning").
- D2 `generateWeek` refuses with `.openDraftExists` while a first (basedOn nil) draft is open.
- D3 `recheckOpenPlans()` is public and idempotent; the composition root should call it at
  launch (repairs an R1 interrupted between household save and plan save, which are two
  repositories and not one transaction).
- D4 Lunchbox "kids" = age band child/teen, or role child with no band (ASSUMPTION).
  `setUpSchoolLunches` is declarative (listed children on, everyone else off); removing a
  lunchbox gives former lunchbox kids their family-lunch serving back (could override a manual
  "not eating" for that lunch).
- D5 Mark cooked learning events are T19 (PantryService owns Mark cooked); T18 logs
  swapped/rerolled only. `notEating` editing is not in T18 (AC-6.3 not in its AC list).
- D6 `currentSeriesID()` = series of the most recently created draft/approved plan.

## Verification
- Local: `scripts/check-core.sh --lint-only` green. No build/tests run locally (no toolchain).
- Needs: Linux CI `swift build --build-tests` + `swift test`. Risky spots for the compiler:
  generic `serialized` helper with non-escaping async closures, `withCheckedContinuation` in the
  lock actor, `@testable import OMPServices` in PlanServiceTests (internal `makeWeek`,
  `PlanningEngine`).
