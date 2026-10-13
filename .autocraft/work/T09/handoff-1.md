# T09 handoff 1: independent plan validator (OMPSafetyCheck) - safety-critical

- Branch: local `feat/t09` (worktree `../omp-t09`), from `claude/build-v1` @ c0e9425. Not pushed.
- ACs: AC-4.2, AC-4.3, AC-6.3. ADR 0007.

## What
- `Sources/OMPSafetyCheck/PlanValidator.swift`: `PlanValidator.validate(_ plan: MealPlan, household: Household, library: SafetyCheckLibrary) -> ValidationReport`.
  - Per meal with a recipe, per eater (serving with `notEating == false`, deduped, serving order):
    covering hard rules = `household.rules(covering:)` (member + household scope) filtered to `.hard`.
  - `.excludedTag(tag, ingredient:)` for each ingredient line whose `tags ∪ mayContain` hits the union of excluded tags (optional lines count).
  - `.unverifiedIngredient` when the ingredient is unverified and the eater has >= 1 hard rule (even one with empty excludedTags).
  - Fail closed: `.unknownRecipe` / `.unknownIngredient` for every eater regardless of rules.
  - Deterministic order: meal (plan order) -> eater -> ingredient line (repeat lines once) -> `FoodTag.allCases` order.
  - Report carries `plan.id` and `plan.contentHash`.
- `Sources/OMPSafetyCheck/SafetyCheckLibrary.swift`: `public init(recipes: [Recipe], ingredients: [Ingredient])`; stores only raw line ids and ingredient tag facts. Never reads `declaredTags`; does not use OMPRecipes' `derivedTags`. Duplicate ids merge conservatively (tag union, unverified wins; recipe lines concatenated).
- `Package.swift`: new `OMPSafetyCheckTests` target. OMPSafetyCheck still depends on OMPDomain only.
- `OMPSafetyCheckModule` kept (OMPServices references it); doc comment updated.

## Tests (`Tests/OMPSafetyCheckTests/PlanValidatorTests.swift`, Swift Testing)
Clean plan passes (+ id/hash); no-rules household passes; excluded tag pinpoints meal/member/ingredient; declaredTags ignored both ways; mayContain on optional line; multi-tag ordering; unverified + unrelated rule; unverified + empty rule; unknown recipe; unknown ingredient; notEating ignored; meal with no eaters; household scope; member scope; member+household combine; cross-meal order + repeated line dedupe; duplicate ingredient/recipe merge.

## Verification
- `bash scripts/check-core.sh --lint-only`: OK.
- No Swift toolchain locally: NOT compiled or run. CI (Linux + macOS) is the verification of record.

## Decisions / questions for reviewer
1. Library is a validator-owned struct built from plain arrays (brief allowed this; no new dependency). Callers: `SafetyCheckLibrary(recipes: seed.recipes, ingredients: seed.ingredients)`.
2. A meal with zero eaters produces no violation even if its recipe is unknown (no `memberId` to attach; nobody eats it). Recommend keeping.
3. Unknown ingredient fails closed even for eaters without rules (consistent with unknown recipe). Stricter than AC-4.3's unverified rule; recommend keeping.
4. Active household members missing from a meal's `servings` are not checked (validator trusts servings as the eater list, per AC-6.3). If services should enforce "every active member has a serving", that belongs in T18/T19.
5. Eaters who are soft-deleted or not in the household are still checked against household-scope rules (conservative).
