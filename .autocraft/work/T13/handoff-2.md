# T13 developer handoff 2 (response to review-1)

```
HANDOFF
From: developer            To: pr-reviewer
Status: DONE
Summary: Fixed the CI compile errors (Fixture.error closures), the PlanDiff "moved meal" gap,
  added stale-report preconditions, made MealPlan.status/approval `public package(set)`, fixed
  both NITs. Not compiled locally (no toolchain); lints OK.
Artifacts: local branch feat/t13, see commit below.
Next: lead pushes, CI must be green; re-review.
```

## Responses
- CI RED (`any Error` -> `PlanLifecycleError` in `Fixture.error { try ... }`): fixed. `PlanFixture.error`
  now takes an untyped `() throws -> T`, catches `PlanLifecycleError` and records any other error
  with `Issue.record`. Every call site goes through this helper, so all of them are covered (no
  other test passes closures to typed-throws parameters; `PlanLifecycle.edit`'s `change` closure
  is non-throwing).
- [MINOR] stale reports: doc `- Precondition:` on `approve` and `applySafetyRecheck` (report must
  be produced at call time against current rules; T18 re-validates and must not reuse stored
  reports). Tracking item for T18 left to the lead.
- [MINOR] forgeable approval: `MealPlan.status` and `approval` are now `public package(set)`
  (not `internal(set)`: Core tests are not `@testable` and assign them; `package` keeps them
  writable inside the Core package and read-only to the app). Codable synthesis is unaffected
  (init assigns stored properties). The public memberwise init and decoding can still supply a
  status/approval, so the T12 lint remains the real guard. `blockedBySafety` left public
  (`PlannedMeal` is edited by planner/services).
- [MINOR] moved meals: id pairing now also requires the same date and slot; a move shows as
  `.removed` at the old place and `.added` (or a change) at the new one. Tests `movedMeal` and
  `hashChangeImpliesDiff` (every meal-level mutation that changes the hash yields a non-empty
  `listedChanges`; lock-only yields a non-empty `changes`). Note: a `weekStart`-only change
  alters the hash but no meal; revisions copy `weekStart`, so it is excluded from that test.
- [MINOR] CI comment: left to the lead.
- [QUESTION] seed `contentVersion` -> R1 re-check in T18: agreed (noted in the precondition doc).
- [NIT] applySafetyRecheck message: new `PlanLifecycleError.closedPlan(status:)` used by
  `edit` and `applySafetyRecheck` for superseded/discarded plans (tests updated).
- [NIT] dead default branch: changes are now sorted on `Change.date`/`slot`/meal id directly.
