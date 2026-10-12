# off-my-plate

OffMyPlate: an on-device iOS/iPadOS meal planner for families, with a mandatory food-safety
gate. Product and technical intent: `docs/product-concept.md`, `docs/technical-specification.md`;
the v1 spec is `docs/specs/offmyplate-v1.md` and the architecture `docs/architecture/plan.md`.

## Developing

### Layout (ADR 0004)
- `Packages/Core`: portable Swift package (Foundation only, zero dependencies; builds on Linux
  and Apple platforms). Targets `OMPDomain`, `OMPSafetyCheck`, `OMPRecipes`, `OMPServices`.
- `Packages/Apple`, `App/`: the Apple-only package and the XcodeGen app project (from T02).
- `scripts/`: checks and lints. `.github/workflows/`: CI.

### Requirements
- Core: Swift 6.2 (Xcode 26 on a Mac, or the `swift:6.2-noble` image on Linux).
- Lints: `bash` plus standard `grep`/`sed`; no Swift needed.

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
  is none); `swift test` for Core (extended with the app build and UI tests in T02).

Both run on pushes to `claude/**` and `main`, on pull requests and on demand
(`workflow_dispatch`). Superseded pull-request runs are cancelled; branch pushes always finish.
Nothing reaches `main` until the owner merges the pull request.
