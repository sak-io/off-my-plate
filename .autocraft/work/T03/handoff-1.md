# T03 Domain contracts: developer handoff 1

```
HANDOFF
From: developer            To: pr-reviewer
Status: DONE
Summary: All plan section 3.1 value types (Codable/Sendable/Hashable) in OMPDomain, the
  PlanValidating result types (ValidationReport/Violation), and OMPServices repository
  protocols plus a generic in-memory actor implementation. Tests cover Codable round trips,
  LocalDate arithmetic across month/year/leap boundaries, AC-1.2 onboarding labels/defaults,
  AC-6.2 portion defaults and in-memory CRUD. NOT compiled locally (no Swift toolchain).
Artifacts: local branch feat/t03 (worktree ../omp-t03), commits ffc14ca, b8ee543, 5dd0d9f,
  merge of claude/build-v1; files listed below.
Open items: 1. CI (Linux swift:6.2 + macOS) is the first compile; see "What only CI can verify".
  2. Deviations D1-D7 below need reviewer agreement.
Next: review in a fresh context; the team lead merges feat/t03 and reads the CI result.
```

## What and why
T03 fixes the contracts every later Core task builds on (T04, T07, T08, T09, T13, T17 and the
services). Source of each type: plan section 3.1, ADR 0007 (GateRefusal, ValidationReport),
ADR 0008 (PlanApproval, statuses, series/revision), ADR 0013 (Fact/LearningEvent, soft only),
spec AC-1.2/AC-1.3 (onboarding), AC-6.2 (portions), flows.md "Things the architect must
support" #1 (GateRefusal carries member ids) and #4 (`passedForEveryone` / failing meals).

## Files
Sources (`Packages/Core/Sources/`):
- `OMPDomain/Util/EntityID.swift`: `EntityID<Entity>` phantom-typed string id + `IDTag`.
- `OMPDomain/Util/LocalDate.swift`, `Util/Weekday.swift`, `Util/DomainClock.swift`.
- `OMPDomain/Model/Identifiers.swift` (typealiases `MemberID`, `RecipeID`, ...),
  `FoodTag.swift` (+`TagStatus`), `Restriction.swift`, `Rule.swift`, `Member.swift`
  (`AgeBand`, `SafetyStatus`, `MemberRole`, `MemberLabel`), `Household.swift`
  (`HouseholdSettings`, `HouseholdSizeError`, `Household.onboarding`), `Ingredient.swift`
  (`Aisle`, `StorageLocation`), `Recipe.swift` (`MealType`, `RecipeIngredientLine`,
  `RecipeProvenance`, `RecipeReview`).
- `OMPDomain/Units/MeasureUnit.swift` (+`MeasureDimension`).
- `OMPDomain/Plan/MealPlan.swift` (`MealSlot`, `PlanStatus`, `Approver`, `PlanApproval`,
  `MealServing`, `EmptyMealReason`, `CookRef`, `PlannedMeal`, `MealPlan`),
  `Plan/ExplanationReason.swift`.
- `OMPDomain/Pantry/PantryItem.swift` (`PantryItemRef`, `PantryItemSource`, `PantryItem`,
  `PantryDeduction`, `CookLog`), `Shopping/ShoppingItem.swift`.
- `OMPDomain/Learning/Fact.swift`, `Learning/LearningEvent.swift`, `Prompts/PromptState.swift`.
- `OMPDomain/Safety/GateRefusal.swift`, `Safety/ValidationReport.swift`.
- `OMPServices/Repositories/RepositoryProtocols.swift`, `Repositories/InMemoryRepository.swift`.

Tests: `Tests/OMPDomainTests/{LocalDateTests,UtilTypesTests,Fixtures,CodableRoundTripTests,
ModelBehaviourTests}.swift`, new target `Tests/OMPServicesTests/InMemoryRepositoryTests.swift`.
Manifest: `Packages/Core/Package.swift` (+ `OMPServicesTests` test target only).

## Design choices on the types
- **IDs:** one generic `EntityID<Entity>` (phantom type, String raw value) instead of 15
  hand-written structs. Strings fit both generated ids (lowercased UUID) and seed ids
  (`"paneer"`). Custom Codable encodes a bare string (not `{"rawValue":...}`) and rejects `""`.
  `Comparable` by raw value gives the planner's final deterministic tie-break.
- **LocalDate:** y/m/d; arithmetic is pure integer maths (Hinnant days_from_civil /
  civil_from_days), no `Calendar`, so it is identical on Linux and Apple. The only bridge from
  `Date` is `init(_:in:)` with a required `TimeZone` (uses `secondsFromGMT(for:)`). Encodes
  as strict `"YYYY-MM-DD"`; years limited to 1...9999. `init(daysSinceEpoch:)` preconditions
  the year range (dates are near 2026; out of range is a programming error).
- **DomainClock:** protocol with `now` and a required `timeZone`, `today` derived;
  `SystemClock(timeZone:)` (no default) and `FixedClock`. Nothing defaults to `.current`.
- **Enums with raw String values** for every closed set (stable wire spelling, readable JSON);
  enums with associated values (`RuleScope`, `FactSubject`, `FactStatement`,
  `LearningEventKind`, `ExplanationReason`, `GateRefusal`, `ViolationKind`, `PantryItemRef`)
  use synthesized Codable (Swift 5.5+).
- **No dictionaries keyed by ids in Codable types** (JSONEncoder would write arrays of pairs).
- **Hard rules only on `Household.rules`** (plan V6); `Member` has no allergy field.
  `Rule.init(id:scope:restriction:createdAt:)` snapshots the restriction's tags.
- **AC-1.2:** `Household.onboarding(id:adults:children:now:makeMemberID:)` creates Adult 1..n
  (`ageBand .adult`) then Child 1..n (`ageBand .child`), all `.unasked`, no rules, default
  settings; throws `HouseholdSizeError` outside 1...12 or for negatives (AC-1.3). The id
  factory is injectable for deterministic tests. `nextLabel(for:)` never reuses a number.
- **AC-6.2:** `AgeBand.defaultPortion` (adult/teen/senior 1.0, child 0.6, toddler/infant 0.4),
  `Member.defaultPortion` (override > band > 1.0), `MealServing(defaultFor:)`.
- **ValidationReport** has a `package` initialiser: only Core-package code (OMPSafetyCheck,
  tests) can build one; the Apple package and app cannot. Helpers `passedForEveryone`,
  `violatingMealIDs`. No `PlanValidating` protocol: ADR 0007 says the validator is called
  directly and is not injectable, so T03 provides only its result types.
- **Repositories:** one `Sendable` protocol per entity, all methods `async throws` so the
  SwiftData implementation (OMPData) can use its own actor and surface errors; `save` is an
  upsert. One generic `actor InMemoryRepository<Entity>` conforms to each protocol through
  constrained extensions (insertion-ordered, deterministic). `Repositories` bundles them with
  `inMemory()` and `deleteAll()`.

## Deviations from plan section 3.1 (please confirm)
- D1 `Clock` is named **`DomainClock`**: avoids ambiguity with the standard library's `Clock`
  protocol in modules importing OMPDomain. T08+ use `DomainClock`.
- D2 Units: **`MeasureUnit`** (+`MeasureDimension`) instead of `Unit`/`Dimension`, which clash
  with Foundation classes. T03 defines only cases and dimension; conversions/`Quantity` stay
  in T07. Recipe/pantry/shopping use `quantity: Double` + `unit: MeasureUnit` as in 3.1.
- D3 `Member.label` is a structured **`MemberLabel(role, number)`**, not the English string
  "Adult 1": ADR 0005 keeps user-facing strings out of the core; the UI renders "Adult %lld".
- D4 `PantryItem` uses **`item: PantryItemRef` (`.ingredient(id)` / `.freeText(name)`)** instead
  of `ingredientId?` + `freeTextName?`, so it can never be both or neither. Expiry is
  **`expiresOn: LocalDate?`** (a day, not an instant).
- D5 `LearningEvent` = `id, kind, at` where `kind` is an enum **with its payload as associated
  values** (one type instead of kind + untyped payload). `FactSubject` is household/member
  (G10); recipe/ingredient live in `FactStatement`. `FactStatus` adds `observing` (inferred,
  below threshold) and `forgotten` (tombstone that keeps `forgottenAt`).
- D6 Added small supporting types not named in 3.1: `MealType` (recipe types; lunchbox is a
  slot plus `lunchboxSuitable`), `EmptyMealReason`, `CookRef`, `Approver`, `PantryDeduction`,
  `RecipeIngredientLine/Provenance/Review` (T04 owns the seed schema and may refine),
  `Violation`/`ViolationKind` (adds fail-closed `unknownRecipe`/`unknownIngredient`), `FactKey`,
  `RerollReason`, `ReflectBackAnswer`.
- D7 `GateRefusal` cases carry `[MemberID]` (ADR 0007) rather than `[Member]` (plan 12a #1);
  the UI looks members up by id.

## Evidence (local, Linux, no Swift toolchain)
- `scripts/check-core.sh --lint-only`: all self-tests pass (assert-tests-ran 9/9, bootstrap
  10/10, lints 36/36), `lint-core-imports` OK, `lint-no-network` OK, after merging
  `claude/build-v1` (98d50d8, stricter lints).
- Each `scripts/tests/test-*.sh` run individually: PASS.
- Core was **not** built or tested locally.

## What only CI can verify
- Compilation under Swift 6.2 / Swift 6 language mode on Linux and macOS (strict
  concurrency, synthesized Codable for enums with associated values, `package` access,
  constrained-extension conformances of a generic actor to async protocols, Swift Testing
  parameterised tests with a struct case list and `zip`).
- All new tests passing (about 50 test functions across 2 test targets).
- I double-checked call signatures I was unsure of (`DecodingError.dataCorruptedError(in:
  debugDescription:)`, `TimeZone.secondsFromGMT(for:)`, `TimeZone(secondsFromGMT:)`,
  `rounded(.down)`, `removeAll(where:)`, `#expect(throws:)`, `#require`) and avoided tuple
  literal arguments and `try` inside comparison operands.

## Risks
- First compile happens in CI; a type-check slip is possible in ~2.6k lines. Most likely spots:
  the constrained-extension conformances in `InMemoryRepository.swift` and the multi-tuple
  `zip` test argument.
- `Set` properties encode in hash order (non-deterministic JSON order). Harmless for
  round trips and persistence; the plan content hash (T13) must use its own canonical
  encoding, as ADR 0008 already says.
- Recipe/ingredient field names are a first cut; T04 may rename them with the seed schema.

## Size
31 files, ~2.6k added lines (roughly half tests and fixtures). Split into three commits:
foundations (ids, dates, clock), value types, repositories.
