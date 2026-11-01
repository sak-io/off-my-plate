# W01 spike report: Core on WebAssembly (wasm32-wasi)

**Verdict: GO-WITH-W02.** Core builds for wasm32-wasi with the official Swift 6.2 Wasm SDK. The non-skippable safety suite
(8/8 tests, 3 suites) and OMPDomainTests (396/396) pass under wasmtime, and so do all OMPSafetyCheckTests (29/29) and
OMPRecipesTests (83/83) once the seed files can be read. 92 of 104 OMPServicesTests pass. The 12 that do not are file-system
and one JSON-encoder crash (below), not safety/planner logic.

Evidence: GitHub Actions workflow `core-wasm`, last analysed run on commit 367821b / 19ab845 (branch `claude/ci-w01`);
native `core-linux` and macOS "Swift packages" jobs stayed green with the one shim.

## Working commands (Linux, container `swift:6.2.4-noble`)
The Wasm SDK must come from the *same* toolchain release as the compiler. SDK 6.2-RELEASE with the 6.2.4 image fails with
"module compiled with Swift 6.2 cannot be imported by the Swift 6.2.4 compiler". Use the 6.2.4 SDK with the 6.2.4 image.
```
SDK_URL=https://download.swift.org/swift-6.2.4-release/wasm-sdk/swift-6.2.4-RELEASE/swift-6.2.4-RELEASE_wasm.artifactbundle.tar.gz
# sha256 (computed in CI, pin it): 32fdb8772d73bb174f77b5c59bc88a0d55003d75712832129394d3465158fb43   (6.2.4, 106 MB)
# 6.2.0 SDK, for 6.2.0 image: fe4e8648309fce86ea522e9e0d1dc48e82df6ba6e5743dbf0c53db8429fb5224
swift sdk install "$SDK_URL" --checksum 32fdb877...fb43          # id: swift-6.2.4-RELEASE_wasm
# wasmtime 50.0.1 from github.com/bytecodealliance/wasmtime releases (x86_64-linux tar.xz), on PATH
cd core
swift build --swift-sdk swift-6.2.4-RELEASE_wasm --product OMPServices        # also OMPDomain, OMPSafetyCheck, OMPRecipes
swift build --swift-sdk swift-6.2.4-RELEASE_wasm --build-tests               # one test product: .build/wasm32-unknown-wasip1/debug/CorePackageTests.xctest
```
`swift test --swift-sdk ... ` does NOT work here: SwiftPM tries to exec the .wasm directly ("Exec format error" on
`--dump-tests-json`). Run the test product under wasmtime instead; select Swift Testing explicitly:
```
BD=$PWD/.build/wasm32-unknown-wasip1/debug
wasmtime run --dir=. --dir "$BD" $BD/CorePackageTests.xctest --testing-library swift-testing --filter OMPSafetySuiteTests
# list: ... --testing-library swift-testing --list-tests   (620 test ids; without --testing-library the XCTest runner starts and rejects options)
# faster per-test runs: wasmtime compile X -o tests.cwasm ; wasmtime run --allow-precompiled ...
```
`--dir "$BD"` (the build directory preopened at its own absolute path) is what lets `Bundle.module` find
`Core_OMPRecipes.resources` at run time. Without it: `Fatal error: could not load resource bundle` (kills the whole process,
so every test in the process is lost). That is the W02 problem in miniature: the browser has no such directory.

## Timings (GitHub ubuntu-latest, debug builds)
SDK install ~10 s; wasmtime download ~1 s; build of each library product ~25-30 s (from a shared build); `--build-tests` ~70-90 s;
`.xctest` wasm is 102 MB (debug, all tests + Foundation statically linked), 176 MB precompiled `.cwasm`; `wasmtime compile`
70-130 s. Test run times under wasmtime (debug, Cranelift): OMPDomainTests (396) 5-10 s; **OMPSafetySuiteTests (8 tests incl.
500 generated households) 126-154 s** (native: seconds). A release build was not measured; W02 should expect the safety suite
to be much faster there, and CI should run it in release or accept ~2.5 min.

## Test results (per-test, each test in its own wasmtime process)
| Target | Pass / total | Notes |
|---|---|---|
| OMPDomainTests | 396 / 396 (whole target in one process) | no seed needed |
| OMPSafetySuiteTests | 8 / 8 | needs seed; passes only with the shim and `--dir` below |
| OMPSafetyCheckTests | 29 / 29 | |
| OMPRecipesTests | 83 / 83 | |
| OMPServicesTests | 92 / 104 | 12 failures listed below |

Before the shim the same run was 3/8 safety, 51 of 83 Recipes, 13 of 104 Services failing, all with `NSCocoaErrorDomain 260`
on a path ending `catalog.jso` (see gap 1), i.e. "needs seed bundle (W02)".

### The 12 failing OMPServicesTests (all REAL Wasm problems, none is a safety/planner assertion)
- `DataServiceTests/deleteAllLeavesNothing`: runtime crash `failed to demangle witness for associated type 'Iterator' in
  conformance 'Swift.Array<FoundationEssentials.JSONEncoder.OutputFormatting>: Sequence'` (metadata/reflection problem in the
  debug Wasm build; the same `[.sortedKeys]` encoder works in the probe, so the trigger is a specific generic path). Not isolated.
- `DirectoryInboxStorageTests/deleteAllRemovesRoot`: `FileManager.removeItem` on a directory tree: Cocoa 3328 "not supported".
- `DirectoryInboxStorageTests/pruneKeepsNewest`: `contentsOfDirectory`/enumeration of `failed/`: POSIX 58 "Not supported".
- `DirectoryInboxStorageTests/symlinkIsNotFollowed`: creating/reading a symlink: Cocoa 513 (WASI has no symlink support in wasmtime's default sandbox).
- `ImportServiceTests/{attemptsAreBounded,drainIsBounded,quarantineIsBounded,stuckFilesDoNotFillTheCap}`,
  `OnboardingFlowTests/{addedMemberBlocksPlanning,endToEnd}`, `PlanServiceTests/editApprovedCreatesRevision`,
  `SafetyRecheckTests/ruleAddedAfterApproval`: process aborts (exit 134, "failed to run main module"). The first four use the
  directory inbox (same file-system gaps); the root cause of the other four was not isolated (no message captured).
All twelve exercise the on-disk inbox / persistence path (`DirectoryInboxStorage`, file stores), which a browser app replaces
(IndexedDB/OPFS) anyway; W02 should keep those behind the storage protocols and not run them in the Wasm test set.

## Shim in core/ (the only change; native unaffected, core-linux and macOS jobs green)
`core/Sources/OMPRecipes/SeedLibrary.swift`, `SeedLoader.bundledURL`: the call
`bundle.url(forResource:withExtension:subdirectory:)` is wrapped in `#if !os(WASI)`; WASI uses the existing fallback
(`bundle.resourceURL` + `seed/<file>`). Reason: gap 1.

## Foundation / API gaps found
1. **`Bundle.url(forResource:withExtension:subdirectory:)` returns a path one character short** on WASI
   (`.../seed/catalog.jso`; `resourceURL` and every other path API are correct). Real swift-foundation bug on WASI.
   `Bundle.module` itself exists but only resolves directories on the real file system (needs `--dir`); in a browser it will not.
2. File system: `removeItem` of directories (3328), directory enumeration of a subdirectory (POSIX 58), symlinks (513).
   `FileManager.contents(atPath:)`, `fileExists`, `Data(contentsOf:)`, `String(contentsOfFile:)` work.
3. `Thread` does not exist (compile error `cannot find 'Thread' in scope`); `NSLock` works.
4. `Int` is 32 bit (`MemoryLayout<Int>.size == 4`, `Int.max == 2147483647`): audit any Int arithmetic, hashing and Date-in-ms math in Core.
5. `TimeZone.current` is `GMT` and `Locale.current` is `en_001` (no host environment). Named zones work in the probe
   (`Asia/Kolkata` 19800, `America/Los_Angeles` -28800), so tzdata is available; Core must take time zone and locale
   as explicit inputs (W03 must pass them from JS).
6. Metadata demangling failure above (JSONEncoder.OutputFormatting conformance).
7. Slow in debug: ~15-20x native for the generated-household safety tests.

## Worked fine (probe package built with the same SDK, run under wasmtime; byte-identical to what native would give)
Gregorian `Calendar` fields/arithmetic/`startOfDay` (UTC), `ISO8601DateFormatter`, `DateFormatter` (en_US_POSIX),
`JSONEncoder` `.sortedKeys` / `.prettyPrinted` / `.withoutEscapingSlashes`, `JSONDecoder` `.iso8601`, Unicode
(`lowercased`, diacritic-insensitive folding and search, canonical mapping, grapheme counts), `String(format:)`,
`UUID`, `Date()`, **actors, `withTaskGroup` (100 concurrent increments) and `Task.sleep`** (cooperative single-thread executor:
works, but nothing runs in parallel), `NSLock`.

## Recommendations
- **W02:** replace `Bundle.module` as the only seed source with an injectable loader: `SeedLoader.load(SeedFiles)` already
  exists, so the Wasm entry point should receive the three JSON blobs as bytes from JS and call it. Keep the bundle path for native.
  Gate the file-system based inbox/stores behind protocols so Wasm builds use in-memory repositories (already in OMPServices).
- **W03 export approach:** a single Wasm module with a small, byte-oriented API (JSON in, JSON out) is the safest: `@_expose(wasm, "name")`
  plus `@_cdecl`, or build as a WASI reactor (`-Xclang-linker -mexec-model=reactor`, export `_initialize`); not measured here.
  Pass time zone, locale, "now" and seed bytes from JS explicitly (gap 5). Prefer synchronous exported functions; actors work
  but there are no threads.
- **Size:** debug test wasm is 102 MB; production size not measured. Build with `-c release`, `-Xswiftc -Osize`, `wasm-opt`/`wasm-strip`,
  and consider `--static-swift-stdlib` size reduction (Foundation is the bulk; FoundationEssentials-only builds are smaller). Measure in W03.
- **CI:** keep `core-wasm.yml` (branch-triggered now; make it a PR/main job after W02). Pin the SDK sum. Run the safety suite as
  its own step; with release build time should drop well below the 2.5 min above. Keep the toolchain/SDK versions in lock step.
- Add the golden "same week plan, native vs Wasm, byte-identical" to W02 (not done in W01).

## Not determined
- The byte-identical native-vs-Wasm week-plan golden (no test compares native output to Wasm output yet; the
  safety suite and 396 domain tests, which include planner goldens, pass on both, so determinism is supported but not byte-compared).
- Root cause of the four non-inbox crashes (exit 134) and of the demangle failure; release-build timings and wasm size;
  behaviour in a browser/Node runtime (only wasmtime was used).
