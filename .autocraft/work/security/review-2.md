# Review 2: feat/security (tier S, delta 288ed67) - reviewer: pr-reviewer

Ran: scripts/tests/test-lints.sh = 58 passed / 0 failed; lint-safety.sh on the full repo OK in 0.6 s; 141 KB single file in 0.17 s. Swift/macOS not run (no toolchain).

## Round-1 findings
- Lint split-line bypass (MAJOR): FIXED. Crafted trees all FAIL with the right line: `return UserConfirmation\n()`, `foo(confirmation: UserConfirmation\n())`, `typealias UC =\n UserConfirmation`, `UserConfirmation /* c */ ()`, `UserConfirmation//c\n()`, `UserConfirmation\t()`, `UserConfirmation.init()`, `let f = UserConfirmation.init`, nested block comment before it, `.init()` on the next line, multi-line comments/blank lines before it (line numbers correct), `"http://x"; UserConfirmation()` and `"a//b"` on the same line (still caught), escaped quote `"q\"//"`, triple-quoted string with `//` and `/*`, string containing `/*` with a later violation. A violation inside a `//` comment is correctly ignored. The two real approval files and test dirs still PASS.
- `.complete` (MAJOR): FIXED. No CompleteUntilFirstUserAuthentication left anywhere; ShareInboxWriter and the failed/ dir use `.complete` / `.completeFileProtection`, matching ADR 0011 line 10. Comments are accurate (the false "same class" claim is gone). No BGTaskScheduler in the repo, so "foreground drain" holds.
- release-hygiene strings check (MAJOR): FIXED in substance. YAML valid (python yaml loads 4 jobs). `shell: bash` + `set -euo pipefail`, strings written to a file (no SIGPIPE pitfall), self-check with a 26-byte clang-built marker runs BEFORE the real scan and fails the job if undetected, `$RUNNER_TEMP` used, .app path from derived data matches round 1. Pattern list matches the real names in CompositionRoot.swift (OMPUITestInbox/Seed/Speech, UITestInbox/Seed/Speech); `DebugNetworkDenial` matches nothing in non-test sources (harmless, unverified).
- Drain cap starvation (MINOR from round 1) fix: logic is correct, see MAJOR below for the test gap.

## New findings
[MAJOR] No test covers the new stuck-file cap logic in ImportService.drainInbox (the only test change is `#expect(summary.amountsSkipped == 1)`). The behaviour change (stuck files do not use up the 200 cap; attempts capped at 800; `deferred = names.count - position`) is untested: drainIsBounded and quarantineIsBounded have no stuck files. Add a test with a storage that fails `read` (like FailingReadInbox in DirectoryInboxStorageTests:164) for >= 200 early names (sorted before) plus a few good files, asserting all good files are imported in one drain, `stuck.count` is right, and a second case with > 800 stuck files asserting the loop ends and `deferred` equals the unvisited remainder. Without it, reverting to the old cap would not fail any test.
[MINOR] Residual starvation: with >= 800 persistently stuck names sorting first, later files are never reached (bounded, no infinite loop). Note in tracked.md.
[MINOR] Comment stripper does not know raw strings: `let s = #"a"//"#; let c = UserConfirmation()` is reported OK (the `"` inside the raw string ends the string state and `//` hides the rest). Contrived and CODEOWNERS covers the lint file and approval files, but add a note in the script header ("raw strings not understood") or a state for `#"`.
[MINOR] In the workflow, `scan_file` is called inside `if`, where `set -e` is off, so a failing `strings` run on some file counts as "not found". Check `strings` status explicitly (`strings -a "$1" > f || return 2`) and treat 2 as an error. Same for the `find` process substitution.
[NIT] `attempts` and `position` always have the same value in drainInbox; use one variable.
[NIT] The self-check proves that 16+ byte literals are detected; the hook-type-name patterns have no positive control (a Debug build containing them would be one). Acceptable.
[NIT] No Swift 6.2 compile errors spotted (`total != nil` on an Optional works without Equatable; `var`/`let` usage fine).

Apple-package/workflow files are touched: per owner decision this cannot merge until macOS CI is green.

VERDICT: CHANGES REQUESTED
