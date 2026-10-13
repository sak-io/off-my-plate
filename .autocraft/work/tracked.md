# Tracked follow-ups

| From | Item | Target |
|---|---|---|
| T01 review-2 | NIT E: `Data(contentsOf:)`/`String(contentsOf:)`/`InputStream(url:)` can reach the network; cover with a SAST rule | security-auditor |
| T01 follow-up | NIT T1/T2: rare `.current` forms; documented fail-safe false positives | none |
| T02 review-1 | Test the share extension's text detection | T26 |
| T02 review-1 | App Group entitlement likely off in CI simulators (`CODE_SIGNING_ALLOWED=NO`) | T26 |
| T02 review-1 | Switch CI to checksum-verified XcodeGen 2.46.0 download | follow-up |
| T02 review-1 | Lint against `CFBundleURLTypes` / associated domains under `App/` | follow-up |
| T02 review-1 | App icon needed before TestFlight | T29 |
| T03 review-1 (TR-1) | `lint-safety.sh`: `ValidationReport(` only in `Sources/OMPSafetyCheck/` and `Tests/` | T09/T12 |
| T03 review-1 (TR-2) | Atomic multi-entity save/transaction before `approve` ships | T18/T20 |
| T03 review-1 (TR-3) | SafetyGate fails closed when status is confirmed but `safetyConfirmedAt == nil`; test | T08 — DONE (merged) |
| T03 review-1 (TR-4) | OMPData DTOs own persisted format; keep golden tests in step or add DTO goldens | T20 |
| T03 review-1 (TR-5) | Failable `LocalDate.safelyAdding(days:)` before user-entered offsets reach date math | T16/T24 |
| T08 review-2 | Planner entry points (T10–T12) must call `clearance.isValid(for:now:timeZone:)`, not `matches` | T10/T11/T12 |
| T08 review-2 | UI shows the covering rules before `confirmMemberAnswer` | T22 |
| T07 review-2 | `subtracting` returns nil for non-convertible units; callers decide | T11/T14 |
| T13 review-1 | Services re-validate at call time (never reuse a UI-supplied report); seed contentVersion change triggers the R1 re-check; test with a rule changing after validation | T18 |
| T13 review-1 | lint-safety: `PlanApproval(`, `.status = .approved`, `blockedBySafety = false`, `UserConfirmation(` only in PlanLifecycle, the OMPData mapping and tests (planted fixtures) | T12 |
| T13 review-1 | `weekStart`-only change alters the hash but gives an empty diff (revisions copy weekStart) | T23 |
| T05 review-1 | "Certified gluten-free" path for coeliac users (flours currently mayContain gluten) | future |
| T05 handoff-2 | Label/translation for the new `kerala` cuisine chip (C-035b) | T22 |
| T14 review-1 | Exclude optional recipe lines in `forShopping` only (garnish not bought; Mark cooked/safety still see them) | T19 |
| T14 review-1 | Mark cooked deducts expired items first (literal spec) — owner may prefer last | owner / T24 |
| T14 review-1 | Pack-size rounding for the shopping list | future |
| T06 review-1 | Veg + Jain + nut-free breakfast has only 2 options; puttu/idiyappam carry mayContain gluten via rice flour | owner sign-off / content |
| T06 handoff-1 | Regenerate docs/content/seed-review.md with `swift run seed-review-sheet` and diff (was produced by a Python mirror); consider a CI check | T12 / T29 |
| T10 review-1 | WeekPlanner.swift:225 unreachable `?? 0` → explicit precondition | T11 |
| T10 review-1 | `generateWeek` takes `request.weekStart` unchecked; services must pass the clamped `startDate`; note on R8 in plan.md | T18 |
| T15 review-1 | `cappedPrefix` allocates a String per character; resolver compares every term (fine at seed size) | perf, future |
| T20 review-1 | Delete all data is record-level; use `PRAGMA secure_delete` or destroy store files and reopen (AC-16.2) | T27 |
| T20 review-1 | Verify -wal/-shm files get Complete protection on device | T29 (device check) |
| T11 review-1 | Copy for ExplanationReason.lockedMealNoLongerSafe ("Changed: no longer safe for …") | T23 |
