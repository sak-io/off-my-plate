# T04 Seed schema, loader and validator: developer handoff 1

```
HANDOFF
From: developer            To: pr-reviewer
Status: DONE
Summary: OMPRecipes now has seed schema v1 (catalog/ingredients/recipes JSON), a validator
  that reports every defect class, a Bundle.module loader, derived tags, a markdown review
  sheet + `seed-review-sheet` executable, a real production catalog.json (R4, AC-2.5,
  AC-10.3) and a small placeholder ingredient/recipe library. NOT compiled locally (no Swift
  toolchain); lints pass locally (`scripts/check-core.sh --lint-only`).
Artifacts: local branch feat/t04 (worktree ../omp-t04), commit 1dd62b5.
Open items: 1. CI is the first compile (see "CI-only risks"). 2. Deviations D1-D5 need
  reviewer agreement.
Next: review in a fresh context; the lead merges feat/t04 and reads CI.
```

## What and why
Sources: tasks.md T04; plan §2 (layout, `.copy("Resources/seed")`), §3.1 (Ingredient/Recipe/
Restriction), §5 step 3 (derived tags ∪ mayContain), §10 (seed validation); ADR 0010; R4; spec
AC-2.5, AC-10.3, A3.

- `Sources/OMPRecipes/SeedFiles.swift`: `SeedFile`, `SeedFiles` (raw bytes) and the internal
  permissive v1 documents (all fields optional, enums as strings) so that a missing aisle or an
  unknown unit becomes a precise `SeedIssue` instead of an opaque decode failure. The schema is
  documented in a comment there.
- `SeedIssue.swift`: closed `SeedIssue` enum (Hashable, developer-facing descriptions) and
  `SeedLoadError`.
- `SeedValidator.swift`: `validate(_:) -> SeedValidationResult`. Reports all issues; builds a
  `SeedLibrary` only when there are none. Checks: headers (schemaVersion 1, shared
  contentVersion), catalog completeness (every FoodTag, every Aisle in `Aisle.allCases` order),
  restriction ids/labels/tags, keyword targets, ingredient required fields (name, tags,
  tagStatus, aisle, defaultUnit, defaultLocation), positive densities, ambiguous names/synonyms,
  recipe fields, dangling ingredients, unknown units, positive quantities for quantified units,
  unit convertibility (mass/volume needs gramsPerMl, mass/count gramsPerPiece), region is a
  catalog cuisine, `declaredTags == derived` (both directions reported), signedOff needs reviewer
  and date.
- `SeedLibrary.swift`: `SeedCatalog` (labels, cuisines, restrictions in chip order,
  `restrictions(forKeyword:)`), `SeedLibrary` (lookup, `derivedTags(of:)` = tags ∪ mayContain
  incl. optional lines, `unverifiedIngredients(of:)`), `SeedLoader` (`bundledFiles()`,
  `loadBundled()`, `load(_:)`).
- `SeedReviewSheet.swift` + `Sources/seed-review-sheet/main.swift`: deterministic markdown sheet
  (restrictions, keywords, per-recipe ingredient/tag table, sign-off line).
  `swift run --package-path Packages/Core seed-review-sheet [out.md]`; exits 1 listing issues.
- `Resources/seed/catalog.json` (production): 20 food tags, 9 aisles (AC-10.3), cuisines
  northIndian/southIndian/westIndian/eastIndian (C-035b minus "A bit of everything", which is
  not a region), the 14 AC-2.5 chips: peanuts, tree-nuts, milk, egg, wheat-gluten (wheat+gluten),
  soy, sesame, mustard, fish, shellfish, beef, pork, vegetarian (egg, fish, shellfish, beef, pork,
  poultry, otherMeat, gelatin), jain (vegetarian + rootVegetable, onion, garlic, mushroom), and
  `restrictionKeywords` ("nuts"/"nut" -> peanuts + tree-nuts, groundnut, kaju, dairy, atta, til,
  rai, prawn, ...).
- `ingredients.json` (16) / `recipes.json` (3: dal-tadka, kanda-poha, jeera-rice), all `draft`:
  placeholders replaced by T05/T06. Hing is `unverified` with mayContain wheat+gluten (R4).
- `Package.swift`: OMPRecipes resources, `seed-review-sheet` executable target, `OMPRecipesTests`.
  No other target touched; Units/ and Safety/ untouched.

## Test evidence (`Packages/Core/Tests/OMPRecipesTests`)
- `SeedValidatorTests` (27 tests): valid fixture builds fully; derived tags; catalog keyword
  lookup; one test per required defect class (dangling id, declaredTags missing a derived tag,
  declaredTags claiming an extra tag, ingredient tag change breaking a recipe, missing aisle,
  unknown aisle, missing tagStatus, missing tags, unknown tag, unknown recipe unit, unknown
  default unit, duplicate ingredient/recipe/restriction id) plus unconvertible unit, zero
  quantity, unknown region, signedOff without reviewer, ambiguous synonym, catalog missing a
  food tag, dangling keyword, schema/content version, malformed JSON, `SeedLoader.load` throws.
  Fixtures are JSON text mutated by exact substring; `mutated` fails if the substring is absent.
- `BundledSeedTests`: loads via `Bundle.module` (runs on Linux CI) and passes the validator;
  AC-2.5 chip ids/order; R4 vegetarian/Jain/"nuts"/hing; every FoodTag excluded by some
  restriction; AC-10.3 aisles and labels; regions are catalog cuisines.
- `ReviewSheetTests`: golden sheet for the fixture library (hand-computed; prints first differing
  line on failure); bundled sheet smoke test.
- Local: `bash scripts/check-core.sh --lint-only` OK. Seed JSON derived==declared cross-checked
  with a throwaway Python script. Swift build/test: CI only.

## CI-only risks
1. First compile of all of this (no local toolchain). Signatures double-checked against T03
   types (Ingredient/Recipe/RecipeReview/RecipeProvenance/Restriction inits, `LocalDate(isoString:)`).
2. `Bundle.module.url(forResource:withExtension:subdirectory: "seed")` on Linux; a
   `resourceURL/seed/<file>` fallback is in place.
3. `exit(1)` in `seed-review-sheet/main.swift` relies on Foundation re-exporting Glibc on Linux
   (Core lint forbids importing Glibc directly).
4. Golden review-sheet text was computed by hand; a mismatch is a test-text fix, not a logic bug,
   unless the diff shows otherwise.

## Deviations (for reviewer agreement)
- D1: Seed JSON uses `optional` on recipe lines (plan §3.1 spelling); the domain field stays
  `isOptional`. Seed documents are separate from the domain Codable shape by design.
- D2: `restrictionKeywords` added to catalog.json to encode R4 "nuts" -> peanuts + tree nuts in
  content rather than parser code; T13's SafetyTextParser should use
  `SeedCatalog.restrictions(forKeyword:)`. No domain type changed.
- D3: `tags` is required on every ingredient (explicit `[]`), stricter than A3's "missing tags ->
  unverified"; missing content is rejected rather than downgraded.
- D4: Coverage targets (8/14/8 split, lunchbox subset, sign-off) are not in the structural
  validator; they belong to T06 tests and the release check (ADR 0010).
- D5: The diff is ~2.5k lines, but ~860 are JSON content and ~700 tests; the Swift source is
  ~900 lines. Not split, because the loader, validator and catalog only make sense together.
