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
scripts/check-core.sh              # lint self-tests, lints, swift build, swift test (Core)
scripts/check-core.sh --lint-only  # the lints only, for machines without Swift
swift test --package-path Packages/Core
```

### Lints (run in CI on every push)
| Script | Fails when |
|---|---|
| `scripts/lint-core-imports.sh` | Core imports anything but Foundation or its own modules (tests may also import `Testing`); Core uses `NSLocalizedString`, `String(localized:)`, `NSPredicate`, `DateFormatter` or `NumberFormatter`; Core declares a package dependency (ADR 0005) |
| `scripts/lint-no-network.sh` | any Swift file in `Packages/` or `App/` imports a network/web/cloud/analytics framework or uses a networking API such as `URLSession`; any remote package dependency (ADR 0002, AC-13.2) |

Each lint is proven to fail on planted violations: `scripts/tests/test-lints.sh` runs it
against `scripts/tests/fixtures/<lint>/clean` (must pass) and every `violation-*` fixture
(must fail). Add a fixture whenever you add a rule.

### No Swift on your Linux machine?
`scripts/bootstrap-swift-linux.sh` is optional and best-effort: it tries the signed swift.org
tarball, then the `swift:6.2-noble` Docker image, and exits 0 with a message if both are
blocked (common in cloud sessions). CI is the verification of record either way.

### Continuous integration
- `core-linux.yml`: `swift:6.2-noble` container; lints, `swift build`, `swift test` for Core.
- `apple-macos.yml`: `macos-15` runner with the newest stable Xcode 26; `swift test` for Core
  (extended with the app build and UI tests in T02).

Both run on every push, on pull requests and on demand (`workflow_dispatch`).
Nothing reaches `main` until the owner merges the pull request.
