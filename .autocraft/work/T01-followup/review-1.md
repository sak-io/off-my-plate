# T01 follow-up review, round 1: CHANGES REQUESTED

Verified on a fresh clone: check-core --lint-only green; lints 36/36; assert-tests-ran 9/9; bootstrap 10/10; empty-dir guard fires. CI fix e4069bd correct (cherry-picked onto claude/build-v1 by the lead). MINOR A fixed.

- [MINOR] 1. lint-core-imports.sh:96: assignment/comparison to implicit `.current` not caught (`c.timeZone = .current`, `c.locale = .autoupdatingCurrent`, `x.timeZone == .current`, `TimeZone! = .current`). Widen type form to `[?!]?`; add `(timeZone|calendar|locale)\s*==?\s*\.(current|autoupdatingCurrent)`; pin in violation-locale-apis.
- [MINOR] 2. (a) lint-core-imports.sh:104 banned-API loop skips any line starting with `/*`; reuse comment_only_re. (b) closed-comment regex `/\*[^*]*\*/` fails on comments containing `*` (`/** doc */ import UIKit`); use `/\*([^*]|\*+[^*/])*\*+/` at lint-core-imports.sh:53 (+ segment-strip sed) and lint-no-network.sh:79. Fixture lines for each.
- [NIT] 3. Document fail-safe false positives in script headers.
- [NIT] 4. `url` with colon on next line — ignore.
