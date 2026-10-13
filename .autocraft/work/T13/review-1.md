# T13 review, round 1: APPROVED (conditional on green CI) — CI RED

Gate integrity confirmed; SHA-256 cross-checked against hashlib (all padding boundaries, 1M × "a"); golden hash verified. D1–D5 accepted.

CI on c5dbdb7: FAILED on Linux and macOS — PlanLifecycleTests.swift (e.g. :238, :272, :276, :281, :285): "invalid conversion of thrown error type 'any Error' to 'PlanLifecycleError'" for closures passed to `Fixture.error { try ... }` (closure thrown type not inferred as PlanLifecycleError).

- [MINOR] Stale reports can approve/clear blocks: doc precondition now on approve/applySafetyRecheck; track T18 (service re-validates at call time, with a test).
- [MINOR] Approval forgeable via public `status`/`approval`/`blockedBySafety`: make `status`/`approval` `public internal(set)` if cheap; track T12 lint.
- [MINOR] PlanDiff misses date/slot moves on the same meal id: fix (pair by id only when date+slot match, or `.moved`); test that a different hash gives a non-empty diff (ignoring lock-only).
- [MINOR] CI paths-ignore comment (lead's change on build-v1) — lead fixes.
- [QUESTION] Seed contentVersion change should trigger R1 re-check → yes, T18.
- [NIT] applySafetyRecheck `expected: .approved` message; [NIT] dead default branch in PlanDiff.
