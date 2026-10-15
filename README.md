# off-my-plate

> Status: Work in progress (WIP)
> This project is not yet ready for use, testing, or production deployment.

OffMyPlate is an iOS/iPadOS household meal planner that helps families plan meals around pantry inventory, dietary rules, and preferences. All 30 planned v1 tasks are built and CI is green, but the app is **not release-ready**: it still needs owner sign-offs and decisions, and a real-device check. See `docs/STATUS.md` for the current status and the list of what is needed.

OffMyPlate: an on-device iOS/iPadOS meal planner for families, with a mandatory food-safety
gate. Product and technical intent: `docs/product-concept.md`, `docs/technical-specification.md`;
the v1 spec is `docs/specs/offmyplate-v1.md` and the architecture `docs/architecture/plan.md`.

## Developing

### Layout (ADR 0004)
- `Packages/Core`: portable Swift package (Foundation only, zero dependencies; builds on Linux
  and Apple platforms). Targets `OMPDomain`, `OMPSafetyCheck`, `OMPRecipes`, `OMPServices`.
- `Packages/Apple`: Apple-only package (iOS 18 / macOS 15), depends on `../Core` by path.
  Targets `OMPData` (SwiftData), `OMPCapture` (speech), `OMPUI` (design system),
  `OMPFeatures` (screens and view models).
- `App/`: the XcodeGen spec `project.yml` (ADR 0006) for the `OffMyPlate` app (universal,
  iOS/iPadOS 18), the `OffMyPlateShare` share extension and the `OffMyPlateUITests` target.
  The `.xcodeproj` is generated and git-ignored.
- `scripts/`: checks and lints. `.github/workflows/`: CI.

### Requirements
- Core: Swift 6.2 (Xcode 26 on a Mac, or the `swift:6.2-noble` image on Linux).
- Lints: `bash` plus standard `grep`/`sed`; no Swift needed.
- App: Xcode 26 and XcodeGen (`brew install xcodegen`; the version the project is developed
  with is in `App/.xcodegen-version`, the minimum in `project.yml`).

### Running the app (Mac)
```sh
cp App/Config/Local.xcconfig.example App/Config/Local.xcconfig   # once; set DEVELOPMENT_TEAM
(cd App && xcodegen generate)                                   # after every project.yml change
open App/OffMyPlate.xcodeproj                                   # scheme OffMyPlate
```
`Local.xcconfig` is git-ignored. It holds your signing team and, if the R6 defaults
(`app.offmyplate.OffMyPlate`, `group.app.offmyplate`) are taken, your own bundle-ID prefix
and App Group. Never commit it.

### Everyday commands
```sh
scripts/check-core.sh              # script self-tests, lints, swift build, swift test (Core)
scripts/check-core.sh --lint-only  # self-tests and lints only, for machines without Swift
swift test --package-path Packages/Core
```

### Lints (run in CI on every push)
| Script | Fails when |
|---|---|
| `scripts/lint-core-imports.sh` | Core imports anything but Foundation or its own modules (tests may also import `Testing`), including Swift 6 `public`/`internal`/... imports; Core uses `NSLocalizedString`, `String(localized:)`, `NSPredicate`, any Foundation `*Formatter`, `.formatted(`, or `Calendar`/`Locale`/`TimeZone` `.current`; Core declares a package dependency (ADR 0005) |
| `scripts/lint-no-network.sh` | any Swift file in `Packages/` or `App/` imports a network/web/cloud/analytics framework or uses a networking API such as `URLSession` or `URLRequest`; any remote dependency in a package manifest (`url:`/`id:`) or XcodeGen spec (`url:`/`github:`) (ADR 0002, AC-13.2) |

Each lint is proven to fail on planted violations: `scripts/tests/test-lints.sh` runs it
against `scripts/tests/fixtures/<lint>/clean` (must pass) and every `violation-*` fixture
(must fail; an optional `expected-output.txt` pins the exact `file:line` and reason).
Add a fixture whenever you add a rule. `check-core.sh` runs every `scripts/tests/test-*.sh`.

`scripts/assert-tests-ran.sh LOG` fails a `swift test` run in which no Swift Testing test
ran; CI and `check-core.sh` apply it after every test step.

### No Swift on your Linux machine?
`scripts/bootstrap-swift-linux.sh` is optional and best-effort: it tries the signed swift.org
tarball, then the `swift:6.2-noble` Docker image, and exits 0 with a message if both are
blocked (common in cloud sessions). CI is the verification of record either way.

### Continuous integration
- `core-linux.yml`: `swift:6.2-noble` container; script self-tests, lints, `swift build`,
  `swift test` for Core (plus the zero-test guard).
- `apple-macos.yml`: `macos-15` runner with the newest stable Xcode 26 (the job fails if there
  is none). Jobs run in parallel: `swift test` for Core and `Packages/Apple`; a Release build
  that must contain no UI-test hooks; and the UI tests, built once and run in shards
  (`scripts/ui-shard-classes.sh`; `--check` fails if a test class is in no shard) on an iPhone 16
  simulator on every push. The iPad simulator shards run on `main`, on manual dispatch, or when
  the head commit message contains the iPad marker (see `work/LESSONS.md`). Simulators are
  picked from the installed runtimes by `scripts/select-simulator.sh` (newest iOS 18+).
  `scripts/assert-xcresult-tests-ran.sh` fails a UI-test run in which no test passed.
Both run on pushes to `claude/**` and `main`, on pull requests and on demand
(`workflow_dispatch`). Superseded pull-request runs are cancelled; branch pushes always finish.
Nothing reaches `main` until the owner merges the pull request.
