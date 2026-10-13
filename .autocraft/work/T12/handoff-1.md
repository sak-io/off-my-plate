# T12 handoff 1: non-skippable safety suite and safety lints

```
HANDOFF
From: developer            To: pr-reviewer
Status: DONE
Summary: New OMPSafetySuiteTests target (restriction × seed recipe × slot with three independent
  verdicts, every restriction pair, 500 generated households, gate refusal for every entry point),
  scripts/lint-safety.sh with 11 planted-violation fixtures, a separate CI "Safety suite" step
  with a minimum test count, and a seed-review sheet check (its own CI job). Safety-critical: full review.
Artifacts: local branch feat/t12 (worktree ../omp-t12), commits dda8940, f10493e, 14c18e6, 857ccdd + this handoff
Open items: see "Risks / for the reviewer" below
Next: review the diff against tasks.md T12 and ADR 0007; run scripts/check-core.sh --lint-only;
  the Swift suite can only run in CI (no local toolchain).
```

## What and why (tasks.md T12; ADR 0007 check (a)-(c); AC-3.1, AC-4.1, AC-4.5, AC-5.6)

### `Packages/Core/Tests/OMPSafetySuiteTests/` (new test target in `Package.swift`)
- `SafetySuiteFixture.swift`: shared helpers. The core is `agreement(...)`: builds **one** plan holding a meal per
  (seed recipe × eating case), validates it once, and compares per meal three verdicts:
  `HardFilter.isSafe` (planner index), `PlanValidator` (raw lines) and an oracle written in the test from
  `SeedLibrary.derivedTags(of:)` / `unverifiedIngredients(of:)`. Also checks `HardFilter.candidates` equals
  "fits the slot ∧ validator-safe". One validation per household keeps it fast in a debug build.
- `RestrictionMatrixTests.swift` (3 tests): every catalog restriction × every recipe × every `MealSlot`, rule on
  child / adult / household (lunchbox and family lunch have different eaters); the generated week for every
  restriction × scope passes and only uses fitting recipes; every restriction pair in three placements (both on
  child, split across members in both orders, household + child): agreement matrix, the week passes, and on a
  quarter of pairs the editing entry points (alternatives, reroll with every reason, regenerate with locks) pass.
  Asserts the exact pair count and that both safe and unsafe verdicts occur (not vacuous).
- `GeneratedHouseholdTests.swift` (2 tests): 500 SplitMix64-seeded households (1–6 members, random age bands,
  school lunches/days, portion overrides, deleted unasked members with rules, 0–3 catalog or ad-hoc tag rules
  with member/household scope, snacks, absences, start date, favourites signals). Run as 10 parameterised
  batches (parallel). Each: gate clears; `generateWeek` passes the validator; agreement matrix over the week's
  distinct eating cases; every 5th household runs all editing entry points; then a member reset to `unasked`
  and the same household 181 days later are refused by the gate (exact ids) and by `generateWeek` with the old
  clearance. A separate test proves the batches cover exactly 500 distinct households.
- `GateRefusalTests.swift` (3 tests): every entry point (`generateWeek`, `alternatives`, `reroll`, `regenerate`)
  × 5 conditions (new unasked member, member reset to unasked, confirmed without date, all overdue, one member
  overdue): baseline call succeeds, then `.clearanceNotValid`; the gate itself refuses each condition with the
  expected `GateRefusal`; an onboarded household is refused.

### `scripts/lint-safety.sh` (+ `scripts/tests/fixtures/safety/`, wired in `test-lints.sh`)
Scans Swift under `Packages/` and `App/` (whole-line comments ignored, no inline escape hatch):
1. every `public`/`package`/`open` func under `OMPDomain/Planner/` has a non-optional `SafetyClearance` parameter,
   except an explicit helper list (`fits`, `startDate`, `dates`, `entry`, `score`, `needsLunchbox`, `slots`,
   `derived`, `replacingRecipe`); multi-line signatures parsed with awk; `// clearance: SafetyClearance` comments
   and `SafetyClearance?` do not count;
2. `SafetyClearance(` / `.init(` / `extension SafetyClearance` only in `Safety/SafetyGate.swift` (not even tests);
3. `ValidationReport(` / `.init(planId:` only in `Sources/OMPSafetyCheck/` and tests; `extension ValidationReport`
   also allowed in its own file;
4. `PlanApproval(`, `status = .approved`, `status: .approved` (MealPlan init), `blockedBySafety = false` only in
   `Plan/PlanLifecycle.swift`, `Packages/Apple/Sources/OMPData/Mapping/` and tests;
5. `UserConfirmation(` / `confirmation: .init(` only in tests and `Packages/Apple/Sources/OMPFeatures/**/Approval*.swift`;
6. no `.disabled`, `withKnownIssue`, `.enabled(` or `#if` in `Tests/OMPSafetySuiteTests/`.
"Tests" = `Packages/<pkg>/Tests/` or `App/<target>Tests/` (a `Tests/` dir inside Sources does not count; fixture proves it).
Proven: clean fixture passes, 10 violation fixtures fail with exact `file:line` + reason (expected-output.txt),
missing dir exits 2, the repository passes. I also mutated a copy of the real repo (`SafetyClearance?` on the
editing entry points) and the lint reported all three.

### CI and scripts
- `core-linux.yml`: new step "Safety suite" runs `swift test --skip-build --filter OMPSafetySuiteTests` and
  `assert-tests-ran.sh` with minimum `SAFETY_SUITE_MIN_TESTS=8` (the suite has 8 `@Test` functions; Swift
  Testing counts a parameterised test once). New job `seed-review` runs `scripts/check-seed-review.sh`.
- `scripts/check-seed-review.sh` (+ `scripts/tests/test-check-seed-review.sh`, 7 cases): compares
  `docs/content/seed-review.md` byte for byte with `swift run seed-review-sheet` output; on a difference prints a
  unified diff and the regenerate command; never rewrites the file (regenerate + owner re-review is a human step).
- `check-core.sh`: header documents lint-safety; full mode also runs the safety-suite step and the seed-review check.

## Architecture deviation (declared)
- **`blockedBySafety = false` is allowed in `Planner/WeekPlanner+Editing.swift`** in addition to the brief's list.
  `replacingRecipe` and `regenerate` clear the flag on a meal whose recipe they just replaced from the hard filter;
  the result is a draft that `OMPServices` validates before display, and `approve` / `applySafetyRecheck` recompute
  the flag. Changing planner behaviour was out of scope; the exception is narrow (one file, one pattern) and
  documented in the script header. Reviewer: accept, or ask for the planner to leave the flag to the lifecycle.
- The planner-entry-point lint applies the ADR's "every public func under Planner/" rule with an explicit helper
  allow-list (the ADR wording would fail on pure helpers like `HardFilter.fits`).
- OMPData allow-list is `OMPData/Mapping/` only (narrower than "OMPData"); widen in a reviewed change if needed.

## Verification
- `bash scripts/check-core.sh --lint-only`: all self-tests pass (test-lints 49/49, test-check-seed-review 7/7) and
  lint-core-imports, lint-no-network, lint-safety pass on the repo.
- No Swift toolchain locally: the suite was not compiled here. Signatures were checked against the sources
  (WeekPlanner/+Editing, HardFilter, PlannerLibrary, SafetyGate, PlanValidator, SafetyCheckLibrary, SeedLibrary,
  Member/Household/Rule/MealPlan inits). CI on the session branch is the verification of record.

## Risks / for the reviewer
1. **The `seed-review` job may fail on its first run**: the committed sheet came from a Python mirror (T06
   handoff). That is the intended signal; fix = regenerate with the printed command, owner re-reviews, commit.
   It is a separate job so the Core job result stays visible.
2. Suite runtime in a debug build is estimated at well under a minute (one validation per household, 10 parallel
   batches, editing on every 5th household / quarter of pairs); please check the CI step duration.
3. If the Swift Testing summary on 6.2 counted parameterised cases differently, the minimum (8) is still a lower
   bound, so the step cannot pass with fewer tests.
4. The main "Test Core" step still runs the suite too (simplest; doubles its time). Could add `--skip` later.
