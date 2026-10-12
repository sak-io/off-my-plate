# T01 follow-up, handoff 2: response to follow-up review round 1

Branch `feat/t01-followup` (local, not pushed). Fix commit: `b6d026c`, on top of `17cf6f1`, no rebase.
`e4069bd` (the CI fixture fix) was already cherry-picked onto `claude/build-v1` by the lead.

## Answers
- **[MINOR] 1. Assignment/comparison to implicit `.current` not caught.** Fixed in b6d026c.
  - The type form is now `(TimeZone|Calendar|Locale)[?!]?\s*=\s*\.(current|autoupdatingCurrent)`.
  - The label form is now `(timeZone|calendar|locale)\s*(:|[!=]?=)\s*\.(current|autoupdatingCurrent)`. It covers argument labels, assignment `=`, and comparison `==` and `!=`.
  - Pinned in `violation-locale-apis`, lines 16–20: `c.timeZone = .current`, `c.locale = .autoupdatingCurrent`, `x.timeZone == .current`, `x.calendar != .current`, `TimeZone! = .current`.
- **[MINOR] 2a. Banned-API loop skipped any line starting with `/*`.** Fixed in b6d026c.
  - The loop now reuses `comment_only_re`, which counts a line as comment-only when it is `//`, a `*` continuation, a `/*` that stays open, or nothing but closed `/* */` comments.
  - Code after a closed comment is checked. Pinned: `violation-locale-apis` line 21, `/* a note */ let late = TimeZone.current`.
  - The clean fixture adds whole-line closed comments that mention `TimeZone.current`, `c.timeZone = .current` and `NSTimeZone.local`, including one with a `*` inside. They still pass.
- **[MINOR] 2b. Closed-comment regex failed on `*` inside a comment.** Fixed in b6d026c.
  - Both lints now use `closed_comment='/\*([^*]|\*+[^*/])*\*+/'` in `stmt_start`, the segment-strip `sed`, `comment_only_re`/`comment_re`, and the no-network `import_re`.
  - Pinned: `/** doc * with a star */ import Combine` (core, line 4) and `/** a * b */ import Network` (no-network, line 3).
  - Clean: `/** the * domain */ import OMPDomain` passes.
- **[NIT] 3. Document fail-safe false positives.** Fixed in b6d026c. Each lint header now says it is text matching, not a parser: a banned name inside a string literal may be reported, but is never silently skipped.
- **[NIT] 4. `url` with the colon on the next line.** Not changing, as the review says to ignore it. Swift style never splits a label from its colon, and the zero-dependency rule plus review covers the rest.

## Evidence (Linux, no Swift)
- **Fail-before**, with the new fixture lines against `17cf6f1`'s lints:
  - `violation-locale-apis` reported 13 of 19.
  - core `violation-same-line-import` reported 3 of 4.
  - no-network `violation-same-line-import` reported 2 of 3.
  - The clean fixture was green before the change and is still green after it.
- After the fix, on a **fresh clone** of `feat/t01-followup`, `scripts/check-core.sh --lint-only` is green:
  - test-assert-tests-ran 9/9
  - test-bootstrap 10/10
  - test-lints 36/36
  - both lints OK on the repo
- No dockerd is running.

## Only CI can verify
Nothing in this change touches Swift code. CI on the merged session branch remains the check for the Swift build and test conditions.

```
HANDOFF
From: developer           To: pr-reviewer
Status: DONE
Summary: Follow-up review 1: MINOR 1 and 2 (a, b) fixed with pinned fail-before fixture lines; NIT 3 header notes added;
  NIT 4 not changed, per the review.
Artifacts: feat/t01-followup @ b6d026c (+ this file); .autocraft/work/T01-followup/handoff-2.md
Open items: none
Next: Re-review in a fresh context on a fresh clone; then the lead merges feat/t01-followup into claude/build-v1.
```
