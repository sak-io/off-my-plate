# W02 report: Wasm correctness, seed bytes, golden plan

Branch `feat/w02` (CI branch `claude/ci-w02`). Last green run: core-linux, core-wasm, seed sheet.

## 1. The 5 "aborts" (hard requirement): root cause = Wasm stack overflow in debug builds

Evidence (CI diagnosis run, wasmtime 50.0.1, WASMTIME_BACKTRACE_DETAILS=1, each test alone):
- Debug build, default link: all five fail with *different*, unrelated symptoms: `memory fault ... out of bounds memory access`
  inside `malloc`/`free`/metadata cache (`swift_getGenericMetadata`, `Set.insert`, `Array.append`, `EnumeratedSequence.makeIterator`,
  `getSuperclassMetadata`) at addresses such as `0x654b677a` (ASCII text, i.e. data read as a pointer), and for
  `deleteAllLeavesNothing` `failed to demangle witness ... Array<JSONEncoder.OutputFormatting>: Sequence from mangled name '!<garbage>ySayxGG'`
  (a corrupted mangled-name string). Different crash site on every test, corrupted metadata/heap: the signature of memory corruption.
- Release build, default link: all five pass.
- Debug build linked with `-z stack-size=1048576` or `8388608`: all five pass, and the whole OMPServicesTests target
  (82 tests in 11 suites, incl. the four ImportServiceTests) passes in one process in 0.5 s.
- Raising wasmtime's own limit (`-W max-wasm-stack=32 MiB`) did not help, so it is not the host stack: it is the guest's shadow stack
  in linear memory. wasm-ld places it after the data by default; an overflow silently overwrites globals and heap
  (mangled names, allocator bookkeeping). Debug async frames are large; release frames are not.

It is therefore a link-configuration problem, not a Core/planner/Foundation bug, and the safety, plan-edit and R1 recheck logic is unchanged.
**Fix** (no Core source change): every Wasm test/executable product is linked with a 4 MiB stack that is placed first in linear memory:
`-Xlinker -z -Xlinker stack-size=4194304 -Xlinker --stack-first -Xlinker --global-base=4194304` (`WASM_LINK` in `core-wasm.yml`).
With `--stack-first` an overflow is a clean trap ("out of bounds memory access" at address near 0) instead of silent corruption.
**W03 must link the web module with the same flags.** The W01 report's belief that four ImportServiceTests were file-system problems was wrong:
they use `InMemoryInboxStorage` and passed once the stack was fixed.

## 2. Seed bytes from the host
- `scripts/gen-seed-embedded.py` turns `Resources/seed/*.json` into `core/Sources/OMPRecipes/SeedEmbedded.generated.swift` (base64; `--check` mode).
- `SeedLoader.embeddedFiles()` decodes it (public, any platform); on WASI `bundledFiles()` returns it, so no `Bundle`
  code is compiled for WASI and the `#if !os(WASI)` shim is gone (no `--dir` for the build directory is needed any more; CI no longer passes it).
  A host may equally call `SeedLoader.load(SeedFiles(...))` with its own bytes. Native keeps `Bundle.module`.
- Test `BundledSeedTests/embeddedEqualsBundle`: native, embedded bytes == bundle bytes and the loaded libraries are equal. This is also the drift check
  (it fails when the JSON changes without regenerating); on Wasm it is trivially true.

## 3. File-system stores
`DirectoryInboxStorage` stays behind `InboxStorage`. Wasm test run excludes exactly three tests (`WASM_SKIP_FS` in the workflow):
`DirectoryInboxStorageTests/deleteAllRemovesRoot` (removeItem of a tree), `.../pruneKeepsNewest` (directory enumeration), `.../symlinkIsNotFollowed` (symlinks).
No `.disabled`/`withKnownIssue` is used; nothing under OMPSafetySuiteTests is touched.

## 4. Golden
`GoldenWeekPlanTests` (OMPServicesTests): embedded seed, household 2 adults + 1 child (child avoids peanuts, cuisine southIndian), deterministic ids,
now = 2026-10-12T00:00:00Z, time zone Asia/Kolkata. The plan JSON (sorted keys, ISO 8601) equals `GoldenWeekPlanFixture.json` (7988 bytes) natively
(core-linux) and on Wasm (core-wasm, debug build). Regenerate with `OMP_GOLDEN_OUT=file swift test --filter weekPlanMatchesGolden`.

## 5. Explicit time zone / locale / now, and 32-bit Int audit
- Core has no host-default reads: `scripts/lint-core-imports.sh` bans `.current`/`autoupdatingCurrent`; `DomainClock` carries `timeZone` and `now`;
  `SystemClock`'s `Date()` is the only wall-clock read and is injected. No locale-dependent API is used in Core.
- Int audit (wasm32 `Int` = 32 bit): planner seed/SHA-256/SplitMix64 use fixed-width `UInt32/UInt64` with wrapping ops; day counts are `Int` but bounded by the
  `LocalDate` year range (about 3 million days); no `hashValue`, no millisecond arithmetic anywhere in Core.
- **Found and fixed:** `ShoppingShareText.amount` computed `Int(min(value, 1e9) * 100)`: up to 1e11, which traps on wasm32 for quantities above ~21.4 million.
  Now `Int64` (identical results natively); test `shareAmounts` extended.

## 6. CI
`core-wasm.yml`: SDK pinned by checksum, wasmtime pinned (`v50.0.1`), library builds, debug+release test builds, safety suite in release as its own step
(asserts >= 8 tests ran), all other tests in debug (asserts >= 600 ran; any failure or abort fails the job), exclusions listed above.

## Not done / follow-ups
- wasmtime tarball is pinned by version, not checksum. Production wasm size and browser/Node behaviour remain W03.
- A worst-case stack-depth measurement was not made; 4 MiB is a safe round value (1 MiB already passes in debug).
