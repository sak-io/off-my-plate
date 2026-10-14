# Tracked follow-ups

| From | Item | Target |
|---|---|---|
| T01 review-2 | NIT E: `Data(contentsOf:)`/`String(contentsOf:)`/`InputStream(url:)` can reach the network; cover with a SAST rule | security-auditor |
| T01 follow-up | NIT T1/T2: rare `.current` forms; documented fail-safe false positives | none |
| T02 review-1 | Test the share extension's text detection | T26 - DONE (`ShareTextDetectionTests` in OMPShareTests) |
| T02 review-1 | App Group entitlement likely off in CI simulators (`CODE_SIGNING_ALLOWED=NO`) | T26 - DONE (tests use temp dirs; UI test uses `-OMPUITestInbox`) |
| T02 review-1 | Switch CI to checksum-verified XcodeGen 2.46.0 download | follow-up |
| T02 review-1 | Lint against `CFBundleURLTypes` / associated domains under `App/` | follow-up |
| T02 review-1 | App icon needed before TestFlight | T29 |
| T03 review-1 (TR-1) | `lint-safety.sh`: `ValidationReport(` only in `Sources/OMPSafetyCheck/` and `Tests/` | T12 — DONE (pending review) |
| T03 review-1 (TR-2) | Atomic multi-entity save/transaction before `approve` ships | T18/T20 |
| T03 review-1 (TR-3) | SafetyGate fails closed when status is confirmed but `safetyConfirmedAt == nil`; test | T08 — DONE (merged) |
| T03 review-1 (TR-4) | OMPData DTOs own persisted format; keep golden tests in step or add DTO goldens | T20 |
| T03 review-1 (TR-5) | Failable `LocalDate.safelyAdding(days:)` before user-entered offsets reach date math | T16/T24 |
| T08 review-2 | Planner entry points (T10–T12) must call `clearance.isValid(for:now:timeZone:)`, not `matches` | T10/T11/T12 |
| T08 review-2 | UI shows the covering rules before `confirmMemberAnswer` | T22 |
| T07 review-2 | `subtracting` returns nil for non-convertible units; callers decide | T11/T14 |
| T13 review-1 | Services re-validate at call time (never reuse a UI-supplied report); seed contentVersion change triggers the R1 re-check; test with a rule changing after validation | T18 |
| T13 review-1 | lint-safety: `PlanApproval(`, `.status = .approved`, `blockedBySafety = false`, `UserConfirmation(` only in PlanLifecycle, the OMPData mapping and tests (planted fixtures) | T12 — DONE (pending review; planner swap exception declared) |
| T13 review-1 | `weekStart`-only change alters the hash but gives an empty diff (revisions copy weekStart) | T23 |
| T05 review-1 | "Certified gluten-free" path for coeliac users (flours currently mayContain gluten) | future |
| T05 handoff-2 | Label/translation for the new `kerala` cuisine chip (C-035b) | T22 |
| T14 review-1 | Exclude optional recipe lines in `forShopping` only (garnish not bought; Mark cooked/safety still see them) | T19 — DONE (already in `IngredientRequirements.forShopping`; `ShoppingEngine`/`PantryService` use it) |
| T14 review-1 | Mark cooked deducts expired items first (literal spec) — owner may prefer last | owner / T24 |
| T14 review-1 | Pack-size rounding for the shopping list | future |
| T06 review-1 | Veg + Jain + nut-free breakfast has only 2 options; puttu/idiyappam carry mayContain gluten via rice flour | owner sign-off / content |
| T06 handoff-1 | Regenerate docs/content/seed-review.md with `swift run seed-review-sheet` and diff (was produced by a Python mirror); consider a CI check | CI check added in T12 (`seed-review` job); regenerating on a diff is a human step |
| T10 review-1 | WeekPlanner.swift:225 unreachable `?? 0` → explicit precondition | T11 |
| T10 review-1 | `generateWeek` takes `request.weekStart` unchecked; services must pass the clamped `startDate`; note on R8 in plan.md | T18 |
| T15 review-1 | `cappedPrefix` allocates a String per character; resolver compares every term (fine at seed size) | perf, future |
| T20 review-1 | Delete all data is record-level; use `PRAGMA secure_delete` or destroy store files and reopen (AC-16.2) | T27 |
| T20 review-1 | Verify -wal/-shm files get Complete protection on device | T29 (device check) |
| T11 review-1 | Copy for ExplanationReason.lockedMealNoLongerSafe ("Changed: no longer safe for …") | T23 |
| T16 review-1 | Safety text "Who?" hint must be shown editable and confirmed (unknown word in name position becomes a hint) | T22 |
| T16 review-1 | Owner sign-off on Malayalam/Hindi restriction keywords (catalog.json) | owner G1 |
| T12 review-1 | `replacingRecipe` (WeekPlanner+Editing.swift:24) is public and clears blockedBySafety without a clearance — make it internal or require a clearance; services validate | T18 / follow-up |
| T12 review-1 | lint-safety PLANNER_HELPERS allow-list keyed by file+name only | follow-up |
| T18 review-1 | App must call `recheckOpenPlans()` at launch before the first UI read; add a test that it repairs an interrupted household-save/plan-recheck | T19: test exists (`ApprovalRevalidationTests.ruleChangedBetweenValidationAndApprove`); the launch call itself is T21 |
| T18 review-1 | `setLocked` computes an unused clearance — add a comment | follow-up |
| T18 review-1 | ASSUMPTION for owner: lunchbox children = child or teen age band | owner |
| T16 delta review | Prepend (Cf, e.g. U+0600) + space may form a non-whitespace-initial Character; extend TranscriptSanitiser and add a test | follow-up |
| T16 delta review | `droppedWords` fixture now sanitises its input (partly circular); keep explicit `describe` assertions | follow-up |
| T21 | Shell audit test ignores Dynamic Type on the system "Plan" label and, on iPad, element-less Dynamic Type issues from the system tab bar (App/OffMyPlateUITests/AppShellUITests.swift, owner-approved 2026-10-14); find the real cause and remove | T28 |
| T19 | Apple layer: implement `ProcessedImportStore` and `CounterStore` over `ProcessedImportRecord`/`CounterRecord`, an `InboxStorage` over the App Group folder (`DirectoryInboxStorage`), and wire `ImportService`, `LearningService`, `DataService` in the composition root; call `DataService.prune()` and `ImportService.drainInbox()` at launch / scene active | T26 - DONE for ImportService (inbox, processed-import store, drain at launch/active); `LearningService`/`DataService` wiring and `prune()` still open (T20 follow-up / T21) |
| T19 | ASSUMPTION for owner: learner `RecipeTraits.keyIngredients` = first two non-optional lines of a recipe (no seed field marks the characteristic ingredients) | owner / content |
| T19 | Import dedupe never edits plan-derived shopping lines (they are recomputed); an imported item whose ingredient is on the plan becomes its own "from Notes" row | owner (UX) |
| T19 | `ImportService` merges before recording the import id: a stop in between merges the file twice on the next drain (visible duplicate preferred to lost items) | follow-up (needs a transactional store) |
| T19 review-1 | `markCooked` is not idempotent after an interruption (deductions + log saved before the cooked ref): repeat deducts twice | follow-up (transactional store) |
| T19 review-1 | Add a test: Mark cooked refuses a `blockedBySafety` meal (rule change after approval -> recheck -> markCooked) | follow-up |
| T19 review-1 | `confirmVoice .add` does not validate ingredient ids against the library and creates duplicate rows for an ingredient already in the pantry | follow-up |
| T19 review-1 | Confirm in T26 that the Share Extension recreates the Inbox folder (`createDirectory`) after "Delete all data" removed it | T26 - DONE (`DirectoryShareInboxWriter`, test `recreatesFolder`) |
| T19 review-1 | `markCooked` accepts caller-edited amounts unchecked (safe: deduct clamps at zero) | none |
| T23 review-1 | **OWNER-VISIBLE DEVIATION:** AC-6.2/6.3 (adjust portions, set a member to "Not eating") are not delivered; portions are read-only in S-11. Cause: Core has no servings-edit service. Proposed Core task: `PlanService.setServings(meal:member:portion:notEating:in:)` through the services + validator; editing an approved plan creates a draft revision (AC-5.4); then steppers in S-11 | owner / new Core task |
| T23 review-1 | Mark cooked button is a no-op until S-15 (`onMarkCooked` nil); consider disabling or a hint if shipped before then | T24 |
| T23 review-1 | Empty-slot reason (AC-4.4) has no UI test (seed cannot make an empty slot); VM test covers toggle only | follow-up |
| T23 review-1 | C-081 shown as a permanent line, not an alert on tap: update screens.md to match | ux-designer |
| T23 review-1 | Number self-coined copy ids in copy.md (C-062b/c, C-070a.*, C-070b.*, C-083.*, C-084.*, C-052.retry, C-063.action, C-071.ok, C-073.*, C-074.replace, C-075.*, C-076.*, C-078.not, C-079.*, plan.slot.*, plan.someone, plan.regenerate); C-065 "View list" action omitted | ux-designer / T24 |
| T23 review-1 | Deferred: C-061 safety summary + Change (with S-33 task); C-040 "Still correct?" card and an Answer-now path for 180-day re-check (T22 flow; button hidden until then); C-082 new-member card; ingredient quantities in S-11 (T24); iPad split view (T28) | T22 / T24 / T28 |
| T23 review-1 | Discard is reachable only from the approval sheet, which cannot open while safety blocks; a pending revision can be neither discarded nor approved until the gate clears (safe direction) | note |
| T23 review-1 | NIT: `swapMealID` not cleared when the swap sheet is swiped away | follow-up |
| T23 | PlanUITests audit ignores element-less issues on iPad (system tab bar/sidebar chrome; any audit type) and Dynamic Type on the system "Plan" label — owner-approved 2026-10-14 (widened from the shell test); find the real cause and remove both exceptions | T28 |
| T26 | ADR 0011 deviation: the extension also links the new `OMPShare` package product (its model, view and inbox writer; depends only on OMPDomain + OMPUI), so the extension logic is unit-testable; `OMPRecipes` is not linked because the app resolves ingredients on drain | architect (ack) |
| T26 | Quarantined (unreadable) inbox files are only logged; ADR 0011 wants them surfaced to the user, but copy.md has no string for it | owner (UX copy) |
| T26 | The import `ServiceContext` has its own lock, separate from the plan backend's and safety services' contexts (existing pattern); imports and plan re-derivation of the shopping list are not mutually serialised | follow-up (share one context in the composition root) |
| T26 | C-111 has no singular; "Added 1 item from Notes." is used for n = 1 | owner (copy) |
| T26 | The Notes-import toast is not covered by an accessibility audit (it hides after 4 s, the audit takes longer) | none |
