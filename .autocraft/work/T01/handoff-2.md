# T01 handoff 2: response to review round 1

Branch `feat/t01` (local, not pushed). Round-1 head was `bb25064`. Fix commits:
`f77aa81` (lints), `0b0f185` (bootstrap), `9e93c26` (CI and zero-test guard).

## Answers, item by item

- **[MAJOR] 1. Access-level imports bypass both lints.** Fixed in f77aa81.
  - Both import regexes now accept an optional `public|package|internal|fileprivate|private` access level after any attributes. `lint-core-imports.sh` takes the module from capture group `\7`, and the group map is written in a comment.
  - New fixtures, each with an `expected-output.txt` that pins file:line, module and exact count:
    - `core-imports/violation-access-level-import`: `internal import UIKit`, `public import SwiftUI`, `@preconcurrency package import os`, `private import struct CryptoKit.SHA256`. All 4 are reported.
    - `no-network/violation-access-level-import`: `public import Network`, `internal import class WebKit.WKNavigation`, `@preconcurrency package import FirebaseCore`. All 3 are reported.
  - The clean fixture now has `public import Foundation` and `internal import struct Foundation.Date`.
- **[MAJOR] 2. Remote package declarations missed.** Fixed in f77aa81.
  - `Package.swift` and `Package@swift-*.swift`: any `url: "` or `id: "` argument on any line is flagged. That covers a multi-line `.package(`, `name:`+`url:`, registry `.package(id:)` and remote `.binaryTarget(url:)`.
  - `project.yml` and `project.yaml`: any `url:` or `github:` key is flagged, in block or flow (`{url: ...}`) style.
  - New fixtures:
    - `violation-package-multiline` (name+url split over lines)
    - `violation-package-registry-id` (a `Package@swift-6.2.swift` with `.package(id:)` and a remote binaryTarget)
    - `violation-project-yml-github` (`project.yaml` with `github:` and a flow-style `url:`)
  - The Core lint also checks `Package@swift-*.swift` (new fixture `violation-versioned-manifest`). The clean XcodeGen fixture has a local `path:` package to prove there is no false positive.
  - `test-lints.sh` no longer hard-codes case names. Each case's optional `expected-output.txt` lists lines that must all appear; without it the case needs `Bad` in the output.
- **[MINOR] 3. More locale-dependent APIs.** Fixed in f77aa81.
  - Now banned in Core sources:
    - every Foundation formatter class (Date, DateComponents, DateInterval, ISO8601Date, RelativeDateTime, Number, Measurement, ByteCount, PersonNameComponents, List, Length, Mass, Energy)
    - `.formatted(`
    - `Calendar`/`Locale`/`TimeZone` `.current`/`.autoupdatingCurrent`
  - I used an explicit list rather than `*Formatter`, so that our own types (for example a future share-text formatter) are not caught.
  - Fixture: `violation-locale-apis` (6 pinned hits). The clean fixture uses `TimeZone(identifier:)`, `Calendar(identifier: .gregorian)`, `formattedName` and `currentTimeZone` as look-alikes that must pass.
  - Note for T03: a system `Clock` must get its `TimeZone` from the app layer.
- **[MINOR] 4. NetworkExtension, FoundationNetworking, URLRequest.** Fixed in f77aa81.
  - Added NetworkExtension and FoundationNetworking to the banned modules, and `URLRequest`, `NSURLRequest`, `NSMutableURLRequest` to the banned symbols.
  - Fixture: `violation-foundationnetworking`.
- **[MINOR] 5. bootstrap leaves the dockerd it started running when the pull fails; retry on 429.** Fixed in 0b0f185.
  - An EXIT trap, plus INT/TERM handling, stops any dockerd this script started on every path except a successful pull. In that case the daemon is kept on purpose and its PID is printed with the `kill` command. Stopping means TERM, waiting up to 15 s, then KILL and `wait`.
  - `docker pull` is retried once after `OMP_PULL_RETRY_DELAY` (default 30 s) when the output says `toomanyrequests`, 429 or rate limit. Other failures are not retried.
  - Evidence: `/usr/bin/dockerd` (pid 8124, started 11:37:51 with `_=/usr/bin/nohup` and `PWD=/home/user/omp-t01`, so the round-1 script) was still running in this container when this round started. That is exactly this bug, probably from the round-1 review run. I stopped it with TERM, and no dockerd is running now.
- **[MINOR] 6. Non-atomic extract.** Fixed in 0b0f185.
  - The tarball is extracted into `mktemp -d "<parent>/.omp-swift-staging.XXXXXX"`, on the same filesystem as the target.
  - The script then checks for `usr/bin/swift` and renames the staging dir into place.
  - A subshell EXIT trap removes the staging dir on any failure or interrupt.
  - An existing non-empty install dir without swift is never touched; an empty one is replaced.
- **[NIT] 7. `mktemp -d` failure.** Fixed in 0b0f185. Both `mktemp` calls are checked, and the script reports the failure and exits 0.
- **[NIT] 8. Pin the swift.org key fingerprint.** Not changing, because I cannot get the current Swift 6.x signing-key fingerprint from a source I trust in this session (swift.org is reachable only through a blocked proxy, and pinning a fingerprint from memory could wrongly reject, or wrongly trust, a key). The script follows swift.org's documented procedure: import `all-keys.asc` over HTTPS and `gpg --verify`, and it never installs an unverified archive. Happy to add a `VALIDSIG` fingerprint check when someone can copy the fingerprint from swift.org.
- **[NIT] 9. Concurrency and push scope.** Fixed in 9e93c26.
  - `cancel-in-progress: ${{ github.event_name == 'pull_request' }}`, so branch pushes always finish and every commit keeps a result.
  - `push` is limited to `claude/**` and `main`; `pull_request` and `workflow_dispatch` are unchanged.
- **[NIT] 10. Fail when Xcode 26 is missing.** Fixed in 9e93c26. The job emits `::error::`, lists the installed Xcodes and exits 1. The header comment is updated to match.
- **[NIT] 11. Pin checkout to a SHA.** Fixed in 9e93c26.
  - Pinned to `actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0`.
  - I resolved it with `git ls-remote https://github.com/actions/checkout 'refs/tags/v4*'`: `refs/tags/v4` and `refs/tags/v4.4.0` both point to that object, and there is no peeled `^{}` entry. They are lightweight tags, so this is the commit SHA.
- **[NIT] 12. Fail CI when 0 tests ran.** Fixed in 9e93c26.
  - New `scripts/assert-tests-ran.sh LOG [MIN]`. It strips ANSI colours, sums every Swift Testing summary `Test run with N test(s)` (6.0 format, 6.1+ "in N suites" format, ✔ or the macOS SF Symbol) and fails when the total is below MIN (default 1) or when no summary exists.
  - XCTest's `Executed 0 tests` line (printed when a target has no XCTest cases) is ignored, so it can neither fail nor satisfy the check.
  - Both workflows and `check-core.sh` run `swift test 2>&1 | tee log` with pipefail, then the guard.
  - `scripts/tests/test-assert-tests-ran.sh` has 9 cases with log fixtures:
    - pass: Linux 6.2 output with XCTest 0, macOS with SF Symbol and ANSI, 6.0 singular, min == count
    - fail: min > count, 0 tests, XCTest-only
    - usage errors: missing log, bad min

## Also changed
- `check-core.sh` runs every `scripts/tests/test-*.sh`, so new self-tests are picked up automatically.
- New `scripts/tests/test-bootstrap.sh`: 10 hermetic cases with fake curl, gpg, docker, dockerd (a `sleep`) and id. It never touches the network, a real daemon or the real `/tmp/omp-dockerd.log`, and it kills every fake daemon on exit.
  - Cases: verified install, bad signature, archive without swift, corrupt archive, existing non-empty dir, mktemp failure, dockerd never ready, 429 retried once, non-429 not retried, successful pull keeps the daemon.
- New bootstrap env settings, documented in its header: `OMP_DOCKERD_LOG`, `OMP_DOCKERD_WAIT`, `OMP_OS_RELEASE`, and `OMP_IGNORE_SWIFT_ON_PATH` (the tests need it because CI's image has swift on PATH).
- README updated.

## Local evidence (Linux, no Swift toolchain)
- `scripts/check-core.sh --lint-only`: green.
  - test-assert-tests-ran 9/9
  - test-bootstrap 10/10
  - test-lints 32/32
  - both lints OK on the repo
- Fail-before:
  - The round-1 lints exit 0 on all 8 new violation fixtures.
  - `test-bootstrap.sh` against the round-1 script: 2 passed, 8 failed (with the env settings patched in so it could run).
- `check-core.sh` with a fake `swift` that prints `Test run with 0 tests`: exit 1. With 2 tests: exit 0.
- No `dockerd` or fake `sleep 300` process is left after any run (checked with `pgrep`).
- Workflows parse as YAML; every script passes `bash -n`.

## Still only verifiable on CI
- Swift build and test of Core on Linux 6.2 and macOS with Xcode 26.
- The real Swift Testing summary line on both platforms. The guard's regex is deliberately loose, but if the format differs the step fails loudly ("no Swift Testing run summary") rather than passing quietly.
- The Xcode 26 selection on `macos-15`.
- The pinned checkout SHA running in both jobs.

## Size
This round adds about 800 lines and removes about 100 (`git diff --stat bb25064`), including these two review documents. Most of it is script tests and fixtures; the Swift code is unchanged.

```
HANDOFF
From: developer           To: pr-reviewer
Status: DONE
Summary: All round-1 items answered: MAJOR 1-2, MINOR 3-6, NIT 7, 9-12 fixed with fail-before fixtures/tests;
  NIT 8 declined with reasoning. New hermetic bootstrap tests and a zero-test guard wired into CI and check-core.
Artifacts: feat/t01 commits f77aa81, 0b0f185, 9e93c26 and this file; .autocraft/work/T01/handoff-2.md
Open items: 1. Swift build/test, the Swift Testing summary format and both CI jobs are verified only once CI runs.
Next: Re-review round 2 in a fresh context; run scripts/check-core.sh --lint-only.
```
