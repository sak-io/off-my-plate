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
