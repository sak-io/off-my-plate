# T01 follow-up, handoff 1: review round 2 findings A, B, C, and a CI-breaking fixture

Branch `feat/t01-followup` (local worktree `../omp-t01fu`, not pushed), from `claude/build-v1` @ 1c159ab.
Source: `.autocraft/work/T01/review-2.md`. Commits: `e4069bd` (fixture), `a18cc68` (A, B, C).

## Found while doing this: CI on 1c159ab will fail (fixed in e4069bd)
- `scripts/tests/fixtures/core-imports/violation-xctest-in-tests` depended on an empty `Sources/OMPDomain/` directory. Git does not track empty directories, so on a fresh checkout the fixture has no `Sources/`.
- `lint-core-imports.sh` then exits 2 (usage error) instead of 1, and `test-lints.sh` fails. The `core-linux` "Script self-tests and lints" step on 1c159ab will go red for this reason.
- I reproduced it on the unmodified merge commit in this fresh worktree (31 passed, 1 failed). The T01 worktree had the directory locally, which is why nobody saw it.
- Fix: a placeholder `Sources/OMPDomain/Ok.swift`.
- Guard: `test-lints.sh` now fails if any fixture directory is empty. I proved it by planting an empty directory: 35 passed, 1 failed, then green again once it was removed.

## Answers
- **[MINOR] A. Manifest `url:`/`id:` required a literal quote.** Fixed in a18cc68.
  - The check now flags `(url|id)\s*:` in `Package.swift` and `Package@swift-*.swift`, whatever the value.
  - New fixture `no-network/violation-package-url-variable` pins 4 hits: a variable, a raw string `#"..."#`, a registry `id:` with a variable, and `url:` with its value on the next line.
- **[MINOR] B. Implicit `.current` forms.** Fixed in a18cc68.
  - Added the narrow patterns from the review: `(TimeZone|Calendar|Locale)\??\s*=\s*\.(current|autoupdatingCurrent)`, `(timeZone|calendar|locale)\s*:\s*\.(current|autoupdatingCurrent)`, and `NS(TimeZone|Locale|Calendar)\.(local|system|default|current|autoupdatingCurrent)`, all with word boundaries.
  - `violation-locale-apis` grows from 6 to 13 pinned hits. The clean fixture adds look-alikes that must pass: `timeZone: TimeZone = kolkata!`, `calendar: Calendar = gregorian`, `TimeZone = .init(secondsFromGMT:)`, `isCurrentWeek`.
- **[NIT] C. Same-line and comment-prefixed imports.** Fixed in a18cc68.
  - Both lints recognise an import after `;` or after closed `/* ... */` comments.
  - `lint-core-imports.sh` splits a line on `;` and reports each import separately.
  - A line starting with `/*` counts as comment-only only while the comment stays open, so `/* x */ import UIKit` is caught, while an open `/* ...; import UIKit` and its `*` continuation lines stay ignored.
  - New fixtures: `violation-same-line-import` in both suites (3 and 2 pinned hits). The clean fixture now has `import Foundation; import OMPDomain` and `/* … */ import OMPDomain`.
- **[NIT] D** (XcodeGen quoted keys and `project.json`) and **[NIT] E** (`Data(contentsOf:)`): not in scope for this follow-up, per the coordinator. E is left to the security-auditor's SAST scan, as the review suggests.

## Evidence (Linux, no Swift)
- `scripts/check-core.sh --lint-only`: green.
  - test-assert-tests-ran 9/9
  - test-bootstrap 10/10
  - test-lints 36/36
  - both lints OK on the repo
- **Fail-before**, with the 1c159ab lints:
  - `violation-locale-apis` gives only 6 violations; the 7 new ones are missed.
  - `violation-same-line-import` (core) and `violation-package-url-variable` / `violation-same-line-import` (no-network) all exit 0.
- No dockerd left running. The bootstrap script was not run outside its hermetic test.

## Only CI can verify
- That `core-linux` is green on this branch's commits once they are merged into `claude/build-v1` (on 1c159ab it is expected red, for the reason above).
- The Swift build/test conditions from review 2 (≥ 2 tests on both platforms) are unchanged by this follow-up.

## Risks
- The `;` split is textual, so a `;` inside a string literal on an import line could yield an odd segment. Only segments that start like an import are checked, so the worst case is a false failure.

```
HANDOFF
From: developer           To: pr-reviewer
Status: DONE
Summary: Review-2 MINOR A/B and NIT C fixed with pinned fail-before fixtures. Also found and fixed a fixture
  that relied on an untracked empty dir, which makes the core-linux lint step red on 1c159ab; added a guard.
Artifacts: feat/t01-followup (e4069bd, a18cc68, this file)
Open items: 1. CI on 1c159ab expected red until this is merged and pushed.
Next: Re-review in a fresh context; run scripts/check-core.sh --lint-only on a FRESH checkout/worktree.
```
