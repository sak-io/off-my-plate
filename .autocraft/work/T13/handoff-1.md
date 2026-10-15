# T13 Plan lifecycle, SHA-256, diff: developer handoff 1

```
HANDOFF
From: developer            To: pr-reviewer
Status: DONE
Summary: Pure-Swift SHA-256 (NIST vectors), the canonical plan encoding + content hash,
  isEffectivelyApproved, PlanLifecycle (approve/discard/supersede/makeRevision/edit/
  applySafetyRecheck/activeApprovedPlan), UserConfirmation, PlanDiff (Was/Now), R1 blocking.
  NOT compiled locally (no Swift toolchain); lints pass (scripts/check-core.sh --lint-only).
Artifacts: local branch feat/t13 (worktree ../omp-t13); files listed below.
Open items: 1. CI is the first compile. 2. Deviations D1-D5 need reviewer agreement.
Next: review in a fresh context; the team lead merges feat/t13 and reads the CI result.
```

## Sources traced
tasks.md T13; plan.md 4.2 + R1/V1; ADR 0008; spec AC-5.1, 5.2, 5.4, 5.5, 5.7, 8.4 (A6);
screens.md S-13 (Was/Now, lock changes not listed); flows.md "architect must support" #2.

## Files
- `Packages/Core/Sources/OMPDomain/Util/SHA256.swift`: `SHA256.hash(_:) -> [UInt8]`,
  `hexDigest(of: String) -> String`, `hexString(_:)`, `digestByteCount`. `&+` arithmetic,
  no imports. Constants verified by script against prime roots; algorithm cross-checked with
  a Python port against hashlib.
- `Packages/Core/Sources/OMPDomain/Plan/PlanContentHash.swift`: `MealPlan.canonicalContent`,
  `.contentHash`, `.isEffectivelyApproved`, `.usableApprovedMeals`; internal
  `PlanCanonicalEncoding` (hand-built sorted-key JSON, byte-wise sorting, JSON escaping,
  `Double.description` for portions with -0.0 normalised).
- `Packages/Core/Sources/OMPDomain/Plan/PlanLifecycle.swift`: `UserConfirmation`,
  `PlanLifecycleError`, `PlanApprovalOutcome`, `PlanLifecycle` (typed throws).
- `Packages/Core/Sources/OMPDomain/Plan/PlanDiff.swift`: `PlanDiff`, `.Change`, `.ChangeKind`.
- Tests (`Packages/Core/Tests/OMPDomainTests/`): `SHA256Tests.swift` (empty, abc, 448-bit,
  896-bit, 1,000,000 x a, padding boundaries 55/56/63/64/65/119/120, UTF-8),
  `PlanFixture.swift`, `PlanContentHashTests.swift` (golden encoding + hash computed
  independently with Python, excluded fields, order independence, every included field
  changes the hash, escaping, tamper/cook/blocked), `PlanLifecycleTests.swift` (each legal
  and illegal transition, same-hash report rule, failing report, revisions, supersede,
  discard, R1 re-check, active plan), `PlanDiffTests.swift` (swap, fill, emptied,
  added/removed, servings x3, lock-only not listed, multi-kind, pairing by date+slot,
  ordering, the S-13 example).

## Design notes / deviations (reviewer please confirm)
- D1 Canonical encoding is hand-built rather than `JSONEncoder(.sortedKeys)`, because
  Foundation's Double/escaping output differs between Linux and Apple. Fields are exactly
  ADR 0008's list; meal ids are NOT in the hash (pairing is the diff's job).
- D2 `blockedBySafety` and `emptyReason` are excluded from the hash (ADR lists only included
  fields). Needed for R1: marking a meal blocked must not void the approval of the rest.
- D3 `approve` clears `blockedBySafety` on all meals: a passing report for this exact hash
  proves the content is safe under current rules.
- D4 `PlanDiff.ChangeKind` adds `.removed` to the task's list; filling an empty slot is
  `.swapped` (Was = no recipe). `isListed`/`listedChanges` drop lock-only changes (S-13).
  Pairing: by meal id, then by date+slot (regenerate may mint new ids).
- D5 Extra API: `PlanLifecycle.edit(_:newRevisionId:now:_:)` (draft edited in place;
  approved -> revision), `applySafetyRecheck` (R1; report must match current hash),
  `activeApprovedPlan(in:series:)`, `MealPlan.usableApprovedMeals`. `UserConfirmation` has a
  public no-arg init; the T12 lint restricts where it is called.

## Verification
- `bash scripts/check-core.sh --lint-only`: OK.
- Swift build/tests: not run (no toolchain); CI is the verification of record.

## What only CI can verify
Typed throws (`throws(PlanLifecycleError)`, `do throws(...)` in `PlanFixture.error`),
parameterized tests, and that the 1M-byte vector runs fast enough in debug (expected < 1 s).
