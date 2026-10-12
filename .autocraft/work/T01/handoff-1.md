# T01 handoff 1: Foundation and walking skeleton (Core + CI)

Branch: `feat/t01` (local worktree, not pushed), based on `claude/build-v1` @ d3df4f2.
Task: `docs/architecture/tasks.md` T01. Sources: plan §2 and §9, ADR 0002, 0004, 0005, 0006.

## What and why
- **`Packages/Core`** (plan §2, ADR 0004/0005): `swift-tools-version: 6.0`, `swiftLanguageModes: [.v6]`,
  platforms iOS 18 / macOS 15, **zero dependencies**. Four library products/targets with the plan's
  dependency graph: `OMPDomain`; `OMPSafetyCheck -> OMPDomain`; `OMPRecipes -> OMPDomain`;
  `OMPServices -> OMPDomain, OMPSafetyCheck, OMPRecipes`. Stubs reference `OMPVersion.current` so each
  dependency edge is compiled from day one.
- **`OMPVersion.current`** = `"0.1.0"`; `Tests/OMPDomainTests/OMPVersionTests.swift` (Swift Testing)
  checks it is `MAJOR.MINOR.PATCH` of ASCII digits and equals `0.1.0`.
- **`.gitignore`**: `*.xcodeproj/`, `xcuserdata/`, `DerivedData/`, `.build/`, `.swiftpm/`, `Local.xcconfig`, OS noise.
- **`scripts/lint-core-imports.sh [CORE_DIR]`**: Sources may import only Foundation and sibling Core
  modules (derived from `Sources/*` directory names, so new targets need no lint change); Tests may
  also import `Testing`. Handles `@testable`/`@preconcurrency`/`@_exported` and `import struct X.Y`.
  Also bans the ADR 0005 non-portable APIs (`NSLocalizedString`, `String(localized:)`, `NSPredicate`,
  `DateFormatter`, `NumberFormatter`) and any `.package(` in Core's `Package.swift`.
- **`scripts/lint-no-network.sh [ROOT]`** (ADR 0002, groundwork for AC-13.2): scans all Swift files,
  `Package.swift` and `project.yml` under `Packages/` and `App/` (sources **and** tests) for imports of
  Network/CFNetwork/WebKit/SafariServices/MultipeerConnectivity/CloudKit and common analytics/HTTP SDKs,
  networking symbols (`URLSession*`, `NSURLConnection`, `NW*`, `CFSocket`, `WKWebView`,
  `SFSafariViewController`, `ASWebAuthenticationSession`, ...), `.package(url:` and `url:` in project.yml.
  No inline allow escape hatch by design.
- Both lints: exit 0 clean / 1 violations (with `file:line: reason`) / 2 usage error; whole-line comments
  ignored; bash 3.2 + POSIX grep/sed so they also run on a Mac.
- **`scripts/tests/test-lints.sh`** + `scripts/tests/fixtures/{core-imports,no-network}/{clean,violation-*}`:
  proves each lint passes on clean input, fails on **every** planted violation and names the offending
  file, treats a missing dir as a usage error, and passes on the real repository.
- **`scripts/check-core.sh [--lint-only]`**: lint self-tests -> every `scripts/lint-*.sh` (auto-discovered,
  so T12's `lint-safety.sh` is picked up) -> `swift build --build-tests` -> `swift test --skip-build`.
  Without Swift on PATH it exits 1 with a clear message (it never reports green when nothing was built).
- **`scripts/bootstrap-swift-linux.sh`**: optional, best-effort. Tries the swift.org Ubuntu 24.04 tarball
  (x86_64/aarch64) and installs it **only if the PGP signature verifies**; then Docker (`swift:6.2-noble`;
  starts `dockerd` only if root, and kills it again if it never becomes ready). Always exits 0 with a
  final status line. Env: `OMP_SWIFT_VERSION` (6.2), `OMP_SWIFT_DIR` (~/.omp-swift), `OMP_SKIP_DOCKER=1`.
- **CI**: `.github/workflows/core-linux.yml` (`swift:6.2-noble` container: toolchain print, `check-core.sh
  --lint-only`, build, test) and `.github/workflows/apple-macos.yml` (`macos-15`: selects the newest stable
  `/Applications/Xcode_26*.app`, falls back to the runner default with a warning; `swift test` for Core).
  Both: `push` on all branches, `pull_request`, `workflow_dispatch`; `concurrency` cancel-in-progress per
  workflow+ref; `timeout-minutes: 30`; `permissions: contents: read`; `actions/checkout@v4` with
  `persist-credentials: false`; no third-party actions.
- **README** "Developing" section.

## How to verify
```sh
scripts/tests/test-lints.sh          # 24 cases, all must pass
scripts/check-core.sh --lint-only    # what CI's lint step runs
scripts/check-core.sh                # full check where a Swift 6.2 toolchain exists
swift test --package-path Packages/Core
```
Plant `let s = URLSession.shared` or `import SwiftUI` in `Packages/Core/Sources/OMPDomain/` and
`check-core.sh --lint-only` must fail.

## Local evidence (this Linux container, no Swift toolchain)
- `scripts/tests/test-lints.sh`: **24 passed, 0 failed** (core-imports: clean + 10 violation fixtures +
  usage error + repo; no-network: clean + 8 violation fixtures + usage error + repo). Each violation
  message was inspected: right file, right line, right module/API (e.g. `@preconcurrency import os` ->
  `'os'`, `import struct CryptoKit.SHA256` -> `'CryptoKit'`).
- Planted `URLSession.shared` and `import SwiftUI` in the real `OMPDomain` sources: `check-core.sh
  --lint-only` exited 1 both times; clean again after removal.
- `check-core.sh` without Swift: exit 1 with the "NOT built or tested" message; `--lint-only`: exit 0;
  unknown option: exit 2.
- `bootstrap-swift-linux.sh`: download.swift.org returned 403; with `OMP_SKIP_DOCKER=1` and with a
  real dockerd attempt (fails: `iptables not found`, daemon killed, no stray process) it exits **0**
  with the final message. Nothing was installed.
- Workflow YAML parses (PyYAML). `bash -n` on all scripts.

## Only CI can verify (not run locally)
- `swift build` / `swift test` of `Packages/Core` on Linux (Swift 6.2) and macOS (Xcode 26):
  the manifest, Swift 6 mode compile of the stubs, and the two `OMPVersionTests` tests.
- That `swift:6.2-noble` resolves, `actions/checkout@v4` works inside it, and the macOS Xcode selection
  finds an Xcode 26 on `macos-15`. Expect both jobs green on the first push of `claude/build-v1`
  after merge; the reviewer/lead should read the run results (`actions_get` / job logs).

## Risks and notes
1. Swift code was written without a compiler. It is deliberately tiny (enum + static lets, one test
   suite); main risk is a manifest typo, which CI will catch immediately.
2. Size: 818 added lines, above the 400-line guideline, but ~100 are fixture files and ~330 are
   commented shell scripts; the Swift is ~90 lines. Splitting would separate the lints from the
   proof that they fail, so I kept one change.
3. `lint-no-network.sh` also scans **test** code. T28's network-denying `URLProtocol` test is fine
   (`URLProtocol` is not banned) but would trip the lint if it references `URLSession`/
   `URLSessionConfiguration`; T28 must then extend the lint deliberately in a reviewed change.
4. The banned lists are deny-lists (best effort); the zero-remote-package rule is the main guard
   against SDKs. Imports inside block comments or string literals can false-positive (fail-safe).
5. `apple-macos.yml` uses `sort -V` on macOS's BSD sort (supported) to pick the newest Xcode 26.
6. `push` on all branches + `pull_request` means PR commits run twice (different concurrency groups).
   Acceptable for now; can be narrowed later.

## Deviations
- None from the architecture. Additions beyond the task text, all from ADR 0005/0002: the core-imports
  lint also bans the listed non-portable APIs and package dependencies; the no-network lint also bans
  WebKit/SafariServices/CloudKit (ADR 0015 deferral) and remote packages in `project.yml`.
- Plan §2's `OMPRecipes` `.copy("Resources/seed")` resource and the `seed-review-sheet` executable,
  and the other test targets, are **not** declared yet: they belong to T04/T03+ and an empty resource
  dir would need a placeholder file. Only `OMPDomainTests` exists.
- `apple-macos.yml` contains only Core `swift test` (XcodeGen/xcodebuild come in T02, as tasks.md says).

```
HANDOFF
From: developer           To: pr-reviewer
Status: DONE
Summary: T01 walking skeleton: Packages/Core (4 stub targets, OMPVersion + Swift Testing test),
  .gitignore, core-imports and no-network lints with fixture-based self-tests proving they fail on
  planted violations, check-core and best-effort bootstrap scripts, core-linux and apple-macos CI, README.
Artifacts: branch feat/t01 (local worktree ../omp-t01); .autocraft/work/T01/handoff-1.md
Open items: 1. Swift build/test and both CI jobs are unverified until CI runs (no local toolchain).
Next: Review in a fresh context; run scripts/tests/test-lints.sh and scripts/check-core.sh --lint-only;
  after merge into claude/build-v1 and push, confirm both workflows are green.
```
