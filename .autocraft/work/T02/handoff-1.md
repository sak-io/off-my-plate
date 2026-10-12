# T02 App walking skeleton, handoff 1

Branch `feat/t02` (local worktree `../omp-t02`, not pushed), from `claude/build-v1` @ eeaa9fb,
with `claude/build-v1` @ 98d50d8 (T01 follow-up lints) merged in (merge, no rebase).
Task: `docs/architecture/tasks.md` T02. Inputs: plan §2, §9, §10, §11, R6; ADRs 0001, 0004, 0006, 0011, 0014.

## What and why
- **`Packages/Apple`** (ADR 0004, plan §2): `Package.swift` (tools 6.0, Swift 6 mode, iOS 18 / macOS 15,
  `.package(path: "../Core")` only).
  - Targets: `OMPData -> OMPDomain, OMPServices`; `OMPCapture -> OMPDomain`; `OMPUI` (no deps);
    `OMPFeatures -> OMPUI, OMPCapture, OMPServices`; test target `OMPDataTests`.
  - Stubs: `OMPDataModule.coreVersion`, `OMPCaptureModule.coreVersion`; `OMPUI.PlaceholderMessage`
    (title + message, header trait, accessibility id); `OMPFeatures.RootView` (NavigationStack:
    home placeholder -> "Open the next screen" -> second placeholder).
  - The stubs only use `OMPVersion.current`, not T03's types or `OMPServicesModule`, so the parallel
    T03 change can't break them.
- **`App/project.yml`** (XcodeGen, ADR 0006):
  - `OffMyPlate` app: iOS 18.0, universal (`TARGETED_DEVICE_FAMILY 1,2`), Swift 6.0.
    Links `OMPFeatures` and `OMPData`, embeds the extension. Scheme `OffMyPlate` runs `OffMyPlateUITests`.
  - `OffMyPlateShare` (`app-extension`): links only `OMPDomain`, `OMPRecipes`, `OMPUI` (plan §2, ADR 0011).
  - `OffMyPlateUITests` (`bundle.ui-testing`).
  - Only local packages. `minimumXcodeGenVersion 2.42.0`; `App/.xcodegen-version` = 2.46.0 (the latest
    release, per the upstream CHANGELOG/Makefile).
- **Config (R6):**
  - `App/Config/Base.xcconfig`: `OMP_BUNDLE_ID_PREFIX = app.offmyplate` (-> `app.offmyplate.OffMyPlate`,
    `.OffMyPlate.Share`, `.OffMyPlateUITests`), `OMP_APP_GROUP_ID = group.app.offmyplate`, empty
    `DEVELOPMENT_TEAM`, and finally `#include? "Local.xcconfig"`.
  - `Local.xcconfig.example` is committed. `Local.xcconfig` was already git-ignored (T01).
- **Entitlements** (app and extension): `com.apple.security.application-groups = [$(OMP_APP_GROUP_ID)]`,
  `com.apple.developer.default-data-protection = NSFileProtectionComplete`.
- **Info.plists:** hand-written and committed so they are reviewable.
  - No `CFBundleURLTypes`: no URL schemes.
  - `ITSAppUsesNonExemptEncryption = false`, `UILaunchScreen`, all iPad orientations (needed for split view).
  - `OMPAppGroupIdentifier = $(OMP_APP_GROUP_ID)`, so T26 can read the group ID at runtime.
  - Extension: `com.apple.share-services`, activation rule `NSExtensionActivationSupportsText`,
    principal class `$(PRODUCT_MODULE_NAME).ShareViewController`.
- **`PrivacyInfo.xcprivacy`** (app and extension, ADR 0014): no tracking, no tracking domains, no
  collected data types, no required-reason APIs yet. A comment says later tasks must add entries in the
  same change. XcodeGen puts `.xcprivacy` in Copy Bundle Resources by default (checked in its
  `SourceGenerator`: unknown extensions -> resources).
- **App code:** `OffMyPlateApp` (`@main`, `WindowGroup { RootView() }`).
- **Extension code:** `ShareViewController` hosts the SwiftUI `ShareSkeletonView` in a `UIHostingController`.
  - It shows "Hello" if any attachment conforms to `UTType.plainText`, else "Text only"; Done completes
    the request.
  - The text isn't loaded yet (T26), which avoids `NSItemProvider` Sendable issues in the skeleton.
- **UI test** `WalkingSkeletonUITests.testLaunchShowsHomeAndNavigatesToSecondScreenAndBack`: launch,
  home title, tap `home.openNext`, second title, back, home again.
- **CI** `apple-macos.yml`: the job is renamed `apple-macos` / "Apple platforms (macOS 15, Xcode 26)",
  timeout 60 min. Steps:
  1. Select Xcode (unchanged).
  2. Core `swift test` + `assert-tests-ran.sh` (kept).
  3. **`Packages/Apple` `swift test` + `assert-tests-ran.sh`.**
  4. Self-test the new CI helpers with `OMP_REQUIRE_PYTHON=1`.
  5. Install XcodeGen.
  6. `xcodegen generate`, then fail if generation touched tracked or untracked files under `App/`.
  7. Pick simulators.
  8. `xcodebuild test` on the iPhone, then on the iPad: `-destination id=<UDID>`, a shared
     `-derivedDataPath`, `-resultBundlePath`, `-parallel-testing-enabled NO`, `CODE_SIGNING_ALLOWED=NO`.
     Each run is followed by the new xcresult zero-test guard.
- **XcodeGen install: `brew install xcodegen`, chosen over a checksum-pinned release zip.**
  - From this sandbox, github.com release downloads, the GitHub API and formulae.brew.sh are all blocked
    (403). I could not compute a real SHA-256, and committing an unverified checksum would be fabricated.
  - Homebrew verifies its bottle SHA-256 from the formula.
  - `HOMEBREW_NO_AUTO_UPDATE=1` uses the image's formula: fast, and no surprise upgrades. If that install
    fails, CI runs `brew update` and retries.
  - `minimumXcodeGenVersion` makes XcodeGen refuse to run if it is too old.
  - If CI's version differs from `App/.xcodegen-version`, the job emits a `::warning::` but does not fail.
    Failing would turn a harmless upstream release into a red build.
- **New scripts, with hermetic self-tests that also run in `check-core.sh` / core-linux:**
  - `scripts/select-simulator.sh FAMILY PREFERRED [MIN_IOS=18]`: parses
    `xcrun simctl list -j devices available` (python3, 3.9-compatible, run with `-I`).
    - Picks an exact-name device on the newest iOS runtime >= 18 that has one.
    - Otherwise picks the first device of the family by name on the newest runtime, and emits a `::warning::`.
    - Ignores non-iOS runtimes and unavailable devices. Exit codes: 1 none found, 2 usage or unreadable list.
    - Test: `scripts/tests/test-select-simulator.sh`, 12 cases, fixtures in `scripts/tests/fixtures/simctl/`.
  - `scripts/assert-xcresult-tests-ran.sh BUNDLE [MIN=1]`: reads
    `xcrun xcresulttool get test-results summary`.
    - Fails if any test failed or fewer than MIN passed (zero tests, or all skipped).
    - Test: `scripts/tests/test-assert-xcresult-tests-ran.sh` with a fake `xcrun`, 10 cases.
  - Both self-tests skip (exit 0) when python3 is missing (the swift image may lack it), unless
    `OMP_REQUIRE_PYTHON=1`. The macOS job sets it.
- README: layout, running the app on a Mac, CI description.

## Local evidence (Linux, no Swift, no Xcode)
- `scripts/check-core.sh --lint-only` after the merge of 98d50d8: green.
  - test-assert-tests-ran 9/9, test-assert-xcresult-tests-ran 10/10, test-bootstrap 10/10,
    test-lints 36/36, test-select-simulator 12/12.
  - `lint-core-imports` OK. `lint-no-network` OK, now scanning `Packages/` **and `App/`**.
- Without python3 on PATH: the self-test skips with exit 0; with `OMP_REQUIRE_PYTHON=1` it fails with exit 1.
- YAML parses (`yaml.safe_load`): both workflows and `App/project.yml`.
- `plistlib` loads both Info.plists, both entitlements files and both privacy manifests.
- XcodeGen spec keys checked against upstream `Docs/ProjectSpec.md`: `packages.path`, dependency
  `package` + `products`/`product`, `scheme.testTargets`, `configFiles`, `options.deploymentTarget`.

## Only macOS CI can verify (nothing Swift/Xcode was compiled or run here)
1. `Packages/Apple` builds on macOS 15 and `OMPDataTests` runs (at least 1 Swift Testing test).
2. `xcodegen generate` accepts the spec, and the generated project builds the app and the extension under
   Swift 6 strict concurrency. Main areas to watch: the `@MainActor` closure in `ShareSkeletonView`, and
   SwiftUI APIs compiled for macOS in OMPUI/OMPFeatures (all are macOS 12+).
3. The UI test passes on the iPhone 16 and on the iPad, and the xcresult summary JSON has the
   field names the guard expects.
4. Generation leaves `App/` clean.
5. Device checks (real share sheet "Hello", Data Protection on a locked device, signing with a real
   team): owner's Mac / T29, not CI.

## Risks
- The UI test runs with `CODE_SIGNING_ALLOWED=NO`, as requested. If XCTest rejects the unsigned runner on
  Xcode 26.3, the fallback is to drop that flag for the simulator steps, so ad-hoc "Sign to Run Locally"
  applies. That needs no team on the simulator, but the App Group entitlement may then need
  `CODE_SIGN_ENTITLEMENTS` cleared for CI.
- If the `xcresulttool test-results summary` schema differs, the guard fails loudly ("unreadable test
  summary") even though the tests passed. The fix is a field-name tweak.
- `iPad (A16)` may not exist on the iOS 26 runtime. The picker then prefers it on an older iOS 18 runtime
  if one is installed, else falls back to another iPad with a warning. The job does not fail.
- Renaming the job changes the check name, "Core (macOS 15, Xcode 26)" -> "Apple platforms (macOS 15,
  Xcode 26)". Update any branch-protection required check.
- No app icon or asset catalog yet. Fine for the simulator; needed before TestFlight (T21/T28).

## Deviations
- **XcodeGen version is pinned softly** (ADR 0006 says "pinned"): `.xcodegen-version` plus
  `minimumXcodeGenVersion`, and a CI warning on mismatch, but no checksum-verified download (see above).
  Recommended follow-up: once someone with GitHub release access computes `shasum -a 256` of
  `xcodegen.zip` 2.46.0, switch CI to a checksum-verified download.
- The extension also ships a `PrivacyInfo.xcprivacy` (the task names one). It is cheap, and the
  extension will write inbox files in T26.
- Extra scripts (`select-simulator.sh`, `assert-xcresult-tests-ran.sh`) were not named in T02. They
  implement the requested robust destination choice and keep T01's "zero tests is a failure" rule
  for XCTest.
- No architecture deviations.

```
HANDOFF
From: developer           To: pr-reviewer
Status: DONE
Summary: Packages/Apple stubs + OMPData test; XcodeGen app (iOS 18 universal) with placeholder home -> second
  screen, share extension saying Hello for text, App Group + Data Protection Complete, privacy manifests, R6
  xcconfig; apple-macos.yml runs both packages' swift test, XcodeGen and xcodebuild UI tests on iPhone 16 + iPad.
Artifacts: feat/t02 (local), .autocraft/work/T02/handoff-1.md
Open items: 1. Swift/Xcode compile and UI tests verifiable only on macOS CI after merge.
  2. XcodeGen pinned softly (brew + version warning); checksum download is a follow-up.
  3. Job/check renamed; update any required-check setting.
Next: Review in a fresh context; run scripts/check-core.sh --lint-only in a fresh worktree; team lead verifies
  apple-macos on GitHub Actions after merge.
```
