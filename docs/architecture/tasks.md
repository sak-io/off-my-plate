# OffMyPlate v1: Work breakdown

Each task is about one reviewable change (aim for < 400 lines; seed-content tasks are data and may be larger, reviewed with the generated sheet). Tags: `[lib]` Core package, `[content]` seed data, `[mobile]` Apple package/app.
**Verify:** `Linux` = passes the `core-linux.yml` job (and locally if a toolchain exists); `macOS` = needs the `apple-macos.yml` job or the owner's Mac. Every task must also be green on macOS CI, because Core runs there too.
Each task's tests are listed; "unit" means Swift Testing in the task's module. ACs refer to `docs/specs/offmyplate-v1.md`; screens S-xx and copy C-xxx refer to `docs/design/`.

## Order and parallelism (max 3 developers)

```
T01 ─┬─ T02 ─────────────────────────────┬─ T20 ─┐
     └─ T03 ─┬─ T04 ─ T05 ─ T06 ─────────┼───────┤
             ├─ T07 ─┬─ T15 ─ T16 ─ T30  │       │
             ├─ T08 ─┤                   │       │
             ├─ T13  ├─ T09 ─ T10 ─ T11 ─┴ T12   │
             └─ T17  └─ T14                      │
   T18 (T08,T09,T11,T13) ─ T19 (T14,T15,T17) ────┤
   T21 (T02) ── T22 · T23 · T24 · T25 · T26 · T27 (3 at a time) ─ T28 ─ T29
```
- **Alone first:** T01.
- **After T01:** T02 ∥ T03.
- **After T03 (contracts are fixed):** pick up to 3 of T04, T07, T08, T13, T17. Then T05, T09, T14, T15, T20, T21 as their dependencies merge.
- **After T18/T19 and T21:** the UI tasks T22–T27, 3 at a time. T28 and T29 come last.

## Tasks

### T01 [lib] Foundation and walking skeleton (Core + CI). Linux
- **Goal:**
  - Repo layout per plan §2.
  - `Packages/Core/Package.swift` with the 4 targets as stubs. `OMPDomain` has `OMPVersion.current`; a trivial test checks it.
  - `.gitignore` (xcodeproj, `.build`, `Local.xcconfig`, DerivedData).
  - `scripts/check-core.sh`, `lint-core-imports.sh`, `lint-no-network.sh`.
  - `scripts/bootstrap-swift-linux.sh`: optional and best-effort; exits 0 with a message when blocked.
  - `.github/workflows/core-linux.yml` (`swift:6.2-noble` container: build, test, lints) and `apple-macos.yml` (`macos-15`: `swift test` for Core; extended in T02).
  - A README "Developing" section.
- **Depends on:** none. **ACs:** groundwork for AC-13.2 (no-network lint), NFR Build.
- **Tests:** trivial unit test; each lint script proven to fail on a planted violation (fixture dir), not just to pass. Both CI jobs green.

### T02 [mobile] App walking skeleton. macOS
- **Goal:**
  - `Packages/Apple` with `OMPData/OMPCapture/OMPUI/OMPFeatures` stubs.
  - `App/project.yml` (XcodeGen): app (iOS 18, universal), `OffMyPlateShare` extension, UI test target, App Group entitlement, Data Protection Complete, `Local.xcconfig.example`, no URL schemes.
  - The app launches to a placeholder home screen and navigates to a second screen. The extension shows "Hello" for text.
  - `apple-macos.yml` runs XcodeGen + `xcodebuild test` (iPhone 16 and iPad simulators).
- **Depends on:** T01. **ACs:** NFR Build; AC-15.5 groundwork.
- **Tests:** one UI test (launch -> second screen); one `OMPData` placeholder test via `swift test` on macOS.

### T03 [lib] Domain contracts. Linux
- **Goal:**
  - All plan §3.1 value types (Codable/Sendable): IDs, `LocalDate`, `Clock`, `Weekday`, `AgeBand`, `FoodTag`, `Restriction`, `Rule`, `Member`, `Household`, `Ingredient`, `Recipe`, `MealPlan`/`PlannedMeal`/`MealServing`/`PlanApproval`, `PantryItem`, `ShoppingItem`, `CookLog`, `Fact`, `LearningEvent`, `PromptState`, `ValidationReport`, `ExplanationReason`, `GateRefusal`.
  - The `PlanValidating` result types.
  - `OMPServices` repository protocols plus in-memory implementations.
- **Depends on:** T01. **ACs:** AC-1.2 (member labels/defaults), AC-6.2 (portion defaults).
- **Tests:** Codable round trips; `LocalDate` arithmetic across month/year/leap boundaries; default portions by age band; in-memory repository CRUD.

### T04 [lib] Seed schema, loader and validator. Linux
- **Goal:**
  - `OMPRecipes`: JSON schema v1 (`catalog.json` with food tags, restrictions -> excluded tags per R4, and aisles per AC-10.3), loader via `Bundle.module`, derived tags.
  - `SeedValidator`.
  - `seed-review-sheet` executable.
  - A small test fixture library.
- **Depends on:** T03. **ACs:** AC-2.5 (chip list), AC-10.3 (aisles), A3.
- **Tests:**
  - The validator rejects each defect class: dangling ingredient id, `declaredTags != derived`, missing aisle or tagStatus, unknown unit, duplicate id.
  - The loader works from `Bundle.module` on Linux.
  - Golden output of the review sheet.

### T05 [content] Ingredient taxonomy (~150). Linux
- **Goal:** Indian pantry ingredients with synonyms and transliterations (dahi/curd/yogurt), tags plus mayContain (conservative: hing -> wheat+gluten; ghee/paneer/curd -> milk; packaged items unverified unless certain), aisle, units, densities/piece weights, default location, shelf life.
- **Depends on:** T04. **ACs:** AC-4.3, AC-10.3, A5, G1.
- **Tests:** full validator pass; spot assertions for known hidden allergens (a list of about 15 pinned facts); every synonym is unique across ingredients.

### T06 [content] 30 seed recipes. Linux
- **Goal:** 8 breakfast, 14 lunch/dinner, 8 lunchbox-suitable original recipes, with provenance and `review.status: draft`, and a generated sign-off sheet committed to `docs/content/seed-review.md`. May be split into two PRs.
- **Depends on:** T05. **ACs:** A2, G1, G5.
- **Tests:**
  - The validator passes and the split counts hold.
  - Each restriction in the catalog leaves at least 1 recipe per meal type, or the test documents the known gap.
  - The "vegetarian + Jain + nut" household has at least 1 recipe per slot type; otherwise the gap is reported for the owner.

### T07 [lib] Units and quantity arithmetic. Linux
- **Goal:** the `Unit` and `Quantity` types; conversions within a dimension and via density/piece weight; add/subtract/scale with clamping at zero; non-quantified units.
- **Depends on:** T03. **ACs:** AC-6.4, AC-9.6, AC-10.1.
- **Tests:** a conversion table; non-convertible quantities kept apart; clamping; floating-point tolerance; property test that a + b − b ≈ a.

### T08 [lib] Safety gate and safety status. Linux
- **Goal:**
  - `SafetyGate.evaluate`, the `SafetyClearance` token (file-private init) and `GateRefusal` with reasons.
  - Status transitions: "No, nobody", confirm rules (including "Not sure who" = household scope), add member -> unasked, age-band crossing -> unasked, 180-day due, "Still correct?" refresh.
- **Depends on:** T03. **ACs:** AC-2.2, AC-2.3, AC-3.1, AC-3.2, AC-3.4, G3.
- **Tests:** every transition; refusal lists the right members; 180-day boundary (day 180 vs 181); clearance snapshot is immutable; a deleted member doesn't block.

### T09 [lib] Independent plan validator (`OMPSafetyCheck`). Linux
- **Goal:** `PlanValidator.validate(plan, household, library) -> ValidationReport`, recomputing tags from the raw ingredient lines. mayContain counts as contains; unverified + any hard rule is a violation; not-eating members are ignored; household-scope rules apply to every eater.
- **Depends on:** T03, T04. **ACs:** AC-4.2, AC-4.3, AC-6.3.
- **Tests:** a hand-built plan per violation class; passes for a clean plan; the report pinpoints meal and member.

### T10 [lib] Planner core. Linux
- **Goal:**
  - Date range (R8): slot expansion (B/L/D, snack flag, lunchbox per school day, lunchbox kids off family lunch per R7, not-eating).
  - Hard filter, greedy selection with seeded tie-breaks, variety rule with relaxation, empty slots with reason, servings.
  - Entry point `generateWeek(clearance:…)`.
- **Depends on:** T08, T04, T09 (for tests). **ACs:** AC-4.1, AC-4.4, AC-4.6, AC-6.1, AC-6.2, AC-6.3, AC-7.2 (slots), G5.
- **Tests:** determinism (same seed gives an identical plan); empty-slot behaviour; variety relaxation reason; lunchbox only from the suitable subset; every output passes `PlanValidator`.

### T11 [lib] Planner scoring, explanations, swap/re-roll/regenerate. Linux
- **Goal:** score components and weights (plan §5), `ExplanationReason` (top two), `reroll(reason:)`, `alternatives(limit: 3)`, `regenerate(keepingLocked:)`, all taking a clearance.
- **Depends on:** T10, T07. **ACs:** AC-4.7, AC-8.1, AC-8.2, AC-8.3, AC-12.6.
- **Tests:**
  - Each component isolated.
  - Facts change only scores: the hard-filter output is the same with and without facts.
  - Locked meals are unchanged after regenerate.
  - Re-roll never returns the current recipe.
  - Alternatives are all valid and number ≤ 3.
  - Performance budget (< 200 ms per week on CI).

### T12 [lib] Non-skippable safety suite and safety lints. Linux
- **Goal:**
  - `OMPSafetySuiteTests`: every restriction × every seed recipe × slot; all restriction pairs; 500 seeded generated households; filter vs validator agreement; gate refusal for every entry point (`unasked` and overdue).
  - `scripts/lint-safety.sh` (clearance parameter, `SafetyClearance(` only in the gate, `UserConfirmation(` only in the approval sheet, no `.disabled`/`withKnownIssue` in the suite).
  - A separate CI step with a check that the test count is > 0.
- **Depends on:** T06, T09, T11. **ACs:** AC-3.1, AC-4.1, AC-4.5, AC-5.6, NFR Safety QA.
- **Tests:** the suite itself; each lint proven against a planted violation.

### T13 [lib] Plan lifecycle, SHA-256, diff. Linux
- **Goal:** the `PlanLifecycle` transitions; `UserConfirmation`; the canonical encoding plus SHA-256 (NIST vectors); `isEffectivelyApproved`; revisions/series; `PlanDiff` (Was/Now: swapped, added, emptied, servingsChanged, lockChanged); `blockedBySafety` marking (R1).
- **Depends on:** T03. **ACs:** AC-5.1, AC-5.2, AC-5.4, AC-5.5, AC-5.7, AC-8.4.
- **Tests:**
  - Each legal and illegal transition.
  - Approval requires a passing report for the same hash.
  - Tamper with a meal and it is no longer effectively approved; cooking doesn't change the hash.
  - Diff cases.
  - SHA-256 vectors (empty, "abc", the 448-bit and 1M-"a" vectors).

### T14 [lib] Pantry and shopping arithmetic. Linux
- **Goal:** requirements from the effectively-approved plan only (excluding blocked and cooked meals); need = requirements − usable pantry; Check-you-have; confidence decay; list merge preserving manual items and check-offs; Bought everything; Mark cooked deduction (earliest expiry first, clamp at 0); unresolved pantry items never count.
- **Depends on:** T07, T13. **ACs:** AC-5.3, AC-6.4, AC-9.2, AC-9.6, AC-9.7, AC-10.1, AC-10.2, AC-10.4, AC-10.5, AC-10.6.
- **Tests:** draft plan gives an empty derived list; worked examples per AC; decay boundaries at 7 and 60 days; merge keeps the check-off on an unchanged item and clears it on a changed quantity; deduction never goes negative.

### T15 [lib] Notes parser, ingredient resolver, inbox format. Linux
- **Goal:** `ShoppingTextParser` (plan §8 shapes; 64 KB/500-line caps; checked lines flagged); `IngredientResolver`; `InboxImport v1` encode/decode; file naming.
- **Depends on:** T04, T07. **ACs:** AC-11.1, AC-11.3 (format), AC-11.4 (text-only contract), AC-9.1 (picker search).
- **Tests:** a golden fixture of 40 Notes lines; fuzz with random unicode and length (no crash; caps hold); resolver ranking and synonyms; inbox round trip; unknown `schemaVersion` rejected.

### T16 [lib] Voice grammar and safety text parser. Linux
- **Goal:** `SpokenCommandParser` (ADR 0012, including number words and approve -> `.openApprovalSheet`) and `SafetyTextParser` ("nuts" -> peanut + tree nut, "no beef", "can't have dairy", `.unmapped`).
- **Depends on:** T15. **ACs:** AC-2.3, AC-2.4, AC-5.6, AC-9.4, G9.
- **Tests:**
  - A golden transcript table (≥ 40), including "I bought 2 kg rice and a dozen eggs" -> rice 2 kg, eggs 12.
  - Unparsed remainder.
  - No grammar path yields an approve transition.
  - Unmapped text is never dropped.

### T17 [lib] Facts learner and prompt scheduler. Linux
- **Goal:** `FactLearner` (ADR 0013: weights, half-life, proposal threshold, Forget, Don't ask again) and `PromptScheduler.next` (one card; safety first and exempt; at most 3 per ISO week; 14-day cooldown; lunchbox Yes/No/Not now per U11; at most one reflect-back per week).
- **Depends on:** T03. **ACs:** AC-7.1, AC-7.3, AC-7.4, AC-12.1, AC-12.2, AC-12.3, AC-12.4, AC-12.5.
- **Tests:** threshold boundaries (2 vs 3 events; 1 vs 2 weeks); decay; Forget ignores older evidence; Don't ask again never re-proposes; the learner's signature can't touch rules (compile-level), and 100 dairy swaps produce only a soft Fact; scheduler caps and ordering.

### T18 [lib] Services A: household, safety, planning, approval. Linux
- **Goal:**
  - `HouseholdService` (onboarding create, add/remove member, `gateStatus`).
  - `SafetyService` (answer, edit rules -> re-validate the open draft **and the active approved plan**, R1).
  - `PlanService` (generate/regenerate/reroll/alternatives -> validated draft + report; `workingPlan`, `activeApprovedPlan`, `hasPendingChanges`; edit approved -> revision; `approve(UserConfirmation)`; discard).
  - `LunchboxService`.
  - Learning events emitted.
- **Depends on:** T08, T09, T11, T13. **ACs:** AC-1.2, AC-1.4, AC-1.5, AC-3.1, AC-3.2, AC-3.3, AC-3.5, AC-4.2, AC-5.x, AC-7.2, AC-8.x.
- **Tests:**
  - End to end with in-memory repos: onboarding -> refused -> answer -> draft -> approve.
  - Edit approved -> revision + diff, with the approved plan still active.
  - R1: adding a peanut rule blocks the approved peanut meal and removes it from the list.
  - Gate refusal surfaces the reason.

### T19 [lib] Services B: pantry, shopping, import, learning, data. Linux
- **Goal:** `PantryService` (CRUD, voice confirm-to-save, Mark cooked on approved only), `ShoppingService` (derive/merge, manual add, check, Bought everything, share text), `ImportService.drainInbox -> ImportSummary` (idempotent, quarantine), `LearningService`, `CounterStore`, `DataService.deleteAll`, pruning (> 12 months).
- **Depends on:** T14, T15, T17, T18. **ACs:** AC-9.1–9.4, AC-9.6, AC-10.x, AC-11.3, AC-11.5, AC-12.1, AC-16.2, NFR Storage.
- **Tests:** drain twice gives one merge; a corrupt file goes to `failed/`; imports emit staple events only and never touch rules; share text format golden; delete-all leaves every repo empty; pruning boundary.

### T20 [mobile] OMPData: SwiftData persistence. macOS
- **Goal:** `SchemaV1` records, migration plan, mappers, `@ModelActor` repositories implementing the T03 protocols, store config (app container, Complete protection), `deleteAllData`.
- **Depends on:** T02, T03. Repositories are completed against the T18/T19 protocol usage. **ACs:** AC-16.2, NFR Encryption/Storage, G6 sync-ready.
- **Tests:** the shared repository contract test suite (from T03) run against SwiftData in-memory **and** on-disk; mapper round trips; reopen persists; plan JSON blob versioning; CloudKit-rule lint (no `.unique`).

### T21 [mobile] App shell, design system, composition root. macOS
- **Goal:** `OMPUI` tokens and components per `docs/design/design-system.md`; tab navigation; root gate cover observing `gateStatus`; disclaimer component; String Catalog; composition root wiring the SwiftData repos and services; `Logger` with private interpolation.
- **Depends on:** T02 (wired fully once T18/T20 merge; it can start with in-memory repos). **ACs:** AC-2.6, AC-14.1, AC-15.x groundwork.
- **Tests:** UI test: launch, tabs, gate cover shown when a member is unasked; accessibility audit on the shell.

### T22 [mobile] Onboarding and safety screens (S-01–S-04, S-02b, F1/F4/F5). macOS
- **Depends on:** T18, T21, T16 (T30 for voice input). **ACs:** AC-1.1–1.6, AC-2.1–2.6, AC-3.2, AC-3.4.
- **Tests:** UI tests: the safety screen has no skip/close/back; "No, nobody" leads to a draft; chips -> candidate review -> confirm; unmapped item forces pick or remove; member-limit bounds; added-member variant; view-model state tests.

### T23 [mobile] Plan screens (S-10, S-10b, S-11, S-12, S-13, S-14). macOS
- **Depends on:** T18, T21. **ACs:** AC-4.4, AC-4.7, AC-5.1–5.7, AC-6.1–6.3, AC-7.1–7.2, AC-8.1–8.4, R1 state.
- **Tests:** UI tests: approve whole week; edit approved -> pending banner + diff sheet; Mark cooked absent on a draft; voice "approve it" opens the sheet only; regenerate keeps locked meals; empty-slot reason visible.

### T24 [mobile] Pantry screens and Mark cooked (S-20–S-23, S-15). macOS
- **Depends on:** T19, T21, T30. **ACs:** AC-9.1–9.7.
- **Tests:** UI tests: manual add, unresolved item badge, stale item, voice confirm card (with a fake `SpeechCapture` injected in test builds), denied/unavailable variants, cooked sheet edits the deduction.

### T25 [mobile] Shopping list screen (S-25). macOS
- **Depends on:** T19, T21. **ACs:** AC-10.1–10.7.
- **Tests:** UI tests: no-approved-plan state, aisle groups, Check you have, pending-changes banner, Bought everything updates the pantry, Share presents a text activity.

### T26 [mobile] Share Extension (S-40, F10). macOS
- **Goal:** extension UI (parse -> review -> destination -> confirm -> inbox write); app-side drain on `.active` with toast C-111.
- **Depends on:** T15, T19, T02. **ACs:** AC-11.1–11.5.
- **Tests:** extension view-model tests; UI test that drops an inbox fixture and checks the merge and toast; non-text input gives the unsupported state; the extension's link list is checked to exclude `OMPServices`. Manual: a real Notes share (T29).

### T27 [mobile] Learning and Settings (S-35, S-36, reflect-back card, S-30, S-31, S-33, S-37). macOS
- **Depends on:** T19, T21. **ACs:** AC-3.5, AC-12.2, AC-12.3, AC-12.5, AC-14.1, AC-16.1, AC-16.2.
- **Tests:** UI tests: reflect-back three answers; Forget; edit Fact stays soft; add a person -> gate; delete all -> S-01.

### T28 [mobile] Accessibility, offline, iPad and performance pass. macOS
- **Depends on:** T22–T27. **ACs:** AC-13.1, AC-13.2, AC-15.1–15.5, NFR Cold start/Plan generation.
- **Tests:** `performAccessibilityAudit()` on every screen at AX5 Dynamic Type and in dark mode; a network-denying `URLProtocol` across all UI flows; iPad split view runs; Reduce Motion check; XCTest launch metric.

### T29 [release] Release readiness for TestFlight. macOS + manual
- **Goal:** `PrivacyInfo.xcprivacy`; purpose strings C-136/C-137; privacy nutrition label notes; data map; a `release-readiness` script (fails while any recipe isn't signed off; G1/G4); manual device checklist (plan §10); TestFlight runbook (human upload).
- **Depends on:** T28, T06. **ACs:** G1, G4, NFR Privacy/Children/Permissions.
- **Tests:** the readiness script fails on a draft recipe and passes on a signed-off fixture; manual checklist results recorded.

### T30 [mobile] Speech capture adapter (`OMPCapture`). macOS
- **Goal:** `SpeechCapture` protocol + `SFSpeechRecognizer` implementation with `requiresOnDeviceRecognition = true` (R9); `SpeechAvailability` states; a just-in-time permission flow; a fake for tests.
- **Depends on:** T02, T16. **ACs:** AC-9.4, AC-9.5, AC-2.3 (voice), AC-13.2.
- **Tests:** availability mapping unit tests (protocol-wrapped recogniser); the fake drives the view models; manual on-device offline check in T29.
