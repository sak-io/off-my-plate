## Tasks

### W01 [spike] Spike: Core builds and its tests pass on WebAssembly. Linux
- **Goal:** a CI job (Linux, swift:6.2 image) installs the Swift 6.2 WebAssembly SDK and builds `OMPDomain`, `OMPSafetyCheck`, `OMPRecipes`, `OMPServices` for wasm32-wasi; runs the unit tests and the non-skippable safety suite under a Wasm runtime (wasmtime or node); records timings and every API that does not exist on Wasm (Foundation gaps, Bundle, threads, Date/Calendar behaviour). Decision gate: if the safety suite cannot run on Wasm, stop and report.
- **Depends on:** none. **ACs:** same results as native for the safety suite and the planner goldens (determinism).
- **Tests:** the existing suites, unchanged, passing on Wasm; one golden: a week plan for a seed household is byte-identical between native and Wasm.

### W02 [lib] Seed content embedded as generated Swift (no Bundle). Linux
- **Goal:** `OMPRecipes` can load the seed without `Bundle.module` when built for Wasm: a generator turns `Resources/seed/*.json` into Swift source; a CI check fails if the generated file differs from the JSON; the native build keeps using the bundle (or the same embedded source, if equal in behaviour).
- **Depends on:** W01. **ACs:** ADR 0010 unchanged; sign-off sheet still current.
- **Tests:** loader on embedded data equals loader on bundle data; drift check proven to fail on a planted change.

### W03 [lib] OMPWeb JSON facade including the single approval bridge. Linux
- **Goal:** a new `OMPWeb` target exporting a small set of functions (JSON in, JSON out) over `OMPServices`: household and safety answers, plan generate/edit/regenerate, approval, pantry, shopping, import, learning, delete-all, state export/import for storage. In-memory repositories with snapshot import and export. No third-party dependencies. `UserConfirmation` is created only in ONE file (`ApprovalBridge.swift`) called only by an explicit confirm message; `lint-safety.sh` allow-list and CODEOWNERS are updated for that exact file in this task, with fixtures.
- **Depends on:** W01. **ACs:** AC-5.x (explicit approval), AC-1.x/AC-2.x (mandatory safety), AC-16.x (delete all).
- **Tests:** facade-level tests that mirror the service tests; gate cannot be bypassed through any export; a non-confirm message never approves.

### W04 [web] Web app skeleton: TypeScript build, local storage, PWA shell, Delete all data. Linux
- **Goal:** `Web/` project (TypeScript, no runtime dependencies; dev-time bundler and test tools only), loads the Wasm core, persists snapshots in IndexedDB, service worker for offline, app shell with the four tabs, Content-Security-Policy with `connect-src 'none'`, Delete all data clears storage and caches. Design tokens from `docs/design/design-system.md`.
- **Depends on:** W03. **ACs:** AC-13.1, AC-13.2, AC-16.2.
- **Tests:** browser test (Playwright on Linux) that the app loads offline after first visit and that Delete all data empties storage.

### W05 [web] Onboarding and mandatory safety screens. Linux
- **Goal:** S-01 to S-04, S-02b flows in the browser: the safety question cannot be skipped, closed or bypassed (also by keyboard or the Back button); chips/typed text become candidates, explicit confirm before saving; unmapped item forces pick or remove.
- **Depends on:** W04. **ACs:** AC-1.1-1.6, AC-2.1-2.6, AC-3.2, AC-3.4.
- **Tests:** browser tests for each rule (no skip via Escape, Tab, browser Back, reload); axe audit.

### W06 [web] Plan screens and explicit approval. Linux
- **Goal:** S-10 to S-14: week plan, meal detail, swap, regenerate keeps locked meals, approval sheet, pending revision and diff, blocked-by-safety state with its update card. Approval only from an explicit click on the confirm button in the sheet.
- **Depends on:** W04. **ACs:** AC-4.4, AC-4.7, AC-5.1-5.7, AC-6.1-6.3, AC-7.1-7.2, AC-8.1-8.4.
- **Tests:** browser tests incl. "approve by keyboard Enter on a different control does not approve"; regenerate keeps locked meals; axe audit.

### W07 [web] Pantry and Mark cooked (typed input). Linux
- **Goal:** S-20 to S-23 (typed, no voice) and S-15 Mark cooked on approved plans only.
- **Depends on:** W06. **ACs:** AC-9.x (voice parts excluded and listed as a documented difference).
- **Tests:** browser tests; axe audit.

### W08 [web] Shopping list and Notes import by paste or file. Linux
- **Goal:** S-25 shopping list and share text (copy to clipboard); Notes import by paste or file chooser using the existing parser and inbox format; imports emit staple events only.
- **Depends on:** W06. **ACs:** AC-10.x, AC-11.x.
- **Tests:** browser tests; import idempotency; axe audit.

### W09 [web] Household, learning, settings, disclaimer. Linux
- **Goal:** S-30/31/33/35/36/37 and the reflect-back card; 180-day re-confirmation; Delete all data with confirmation.
- **Depends on:** W06. **ACs:** AC-2.6, AC-12.x, AC-16.x.
- **Tests:** browser tests incl. forgotten facts stay forgotten; axe audit.

### W10 [web] Accessibility pass. Linux
- **Goal:** axe-core on every screen at 200% zoom and 400% reflow, keyboard-only walk-through, visible focus, dark mode and forced-colors, reduced motion, screen-reader labels (NVDA/Narrator checklist items for the manual pass).
- **Depends on:** W05, W06, W07, W08, W09. **ACs:** AC-15.1-15.5.
- **Tests:** Playwright + axe on every route with no waivers.

### W11 [web] Privacy guarantees. Linux
- **Goal:** prove nothing leaves the device: CSP checked in a test, Playwright network-denial test across all flows, offline test, a lint that bans `fetch`/`XMLHttpRequest`/`WebSocket`/`sendBeacon`/`EventSource`/remote URLs in the web sources (except own assets), no analytics, no third-party scripts or fonts.
- **Depends on:** W04. **ACs:** AC-13.2, NFR Privacy.
- **Tests:** lint fixtures (planted violations fail); the browser test sees zero requests beyond own origin assets after the first load.

### W12 [release] Windows release readiness. Linux + manual
- **Goal:** build output (static site), hosting on GitHub Pages or a zip, Windows install guide (Edge/Chrome "Install app"), manual checklist on Windows 10/11 (Edge, Chrome, Firefox, 125% display scaling, high contrast, NVDA/Narrator, offline, Delete all data), privacy/data-map update (browser storage, no backup), release-readiness script covers the web build too.
- **Depends on:** W10, W11. **ACs:** G1, G4, NFR Privacy.
- **Tests:** readiness script; manual checklist results recorded.
