# W04 report: web app skeleton, first browser proof

Branch `feat/w04`, CI branch `claude/ci-w04`, code commit `987beb2` (CI all green, including the new `web-app` workflow). Package `platforms/web/app`.

## 1. What was built
| Piece | File | Notes |
|---|---|---|
| Wasm loader + WASI shim | `src/wasi.ts`, `src/core.ts` | Hand-written WASI preview1 shim (args/environ empty, clock, `crypto.getRandomValues`, fd_write to a log buffer, no preopens; every other import answers ENOSYS). Imports are derived from the module, any non-WASI import is an error. Same reactor protocol as W03 section 5. |
| JSON wrapper | `src/core.ts` | `Core.call(op, args, ctx)`; `ctx` is a required parameter, `makeCtx()` builds it from the clock, `Intl` zone and `navigator.language`. |
| Persistence | `src/store.ts`, `main.ts` | One IndexedDB record (`omp`/`kv`/`snapshot`) holding `state.export`; restored with `state.import` at start; saved after every state-changing op. |
| Service worker | `src/sw.ts`, `scripts/build.mjs` | Precache list and content version stamped at build time, cache-first, navigation falls back to `index.html`, old caches dropped on activate. |
| Shell | `src/main.ts`, `styles.css` | Four tabs (Plan, List, Pantry, Household; arrow-key navigation, ARIA tablist), Household has create-household, the data note and Delete all data (copy C-161). List and Pantry are placeholders (W13+). Design tokens: accent/on-accent light+dark, system fonts, 44 px targets. |
| CSP | `index.html` meta + `scripts/serve.mjs` header | `default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self'; img-src 'self'; manifest-src 'self'; worker-src 'self'; connect-src 'none'; base-uri 'none'; form-action 'none'`. No inline script or style. |
| Delete all data | `store.ts deleteEverything` | Deletes all IndexedDB databases, all Cache Storage caches, local/session storage, unregisters the service worker, then re-instantiates the Wasm module so the in-memory state is gone too. |
| CI | `.github/workflows/web-app.yml` | Job `wasm` (Swift 6.2.4 container, pinned SDK checksum, same flags as web-facade) uploads the module; job `browser` (ubuntu, Node, Playwright 1.49.1, Chromium 131) builds the app and runs the test. |

Dev-only dependencies (pinned, `package-lock.json` committed, `npm ci --ignore-scripts`): `typescript 5.7.2`, `@playwright/test 1.49.1`, `@types/node 22.10.2`. No runtime dependencies, no bundler (plain `tsc`, ES modules). The app only calls facade ops; `UserConfirmation` is not created and `plan.approve` is not wired in this skeleton (W06). `core/` untouched.

## 2. First browser proof (CI run, Chromium 131 headless, Linux)
- The 54 MB reactor module loads, instantiates and answers `omp_version`/`household.get`/`state.export` in real Chromium. The Playwright suite passed (7 tests): first load, four tabs + keyboard, CSP blocks page `fetch`, household persists across reload, offline reload works, Delete all data empties IndexedDB/caches/SW/localStorage, no unexpected console errors.
- Size: **54,402,571 bytes raw; 20.29 MB gzip -6 (what the test server sends), 20.23 MB gzip -9** (swift build step reported 19.34 MB with the CI artifact compression).
- Time (CI runner, local loopback, empty cache): bytes from the service worker to the page 51 ms (already cached by install), `WebAssembly.compile` + instantiate + `_initialize` **92 ms**, page open to engine-ready including the first service-worker install (which downloads the module, gzip) **1.9 s**. Compile is fast because Chromium compiles lazily/tiered; first heavy calls are not measured here. Real-network first download of ~20 MB is the user-visible cost (one time, then cached).
- The Delete-all test confirms the caches hold the module (cache count > 0 before, 0 after).

## 3. Findings and deviations
1. **CSP `connect-src 'none'` blocks the page's own `fetch()` and therefore `instantiateStreaming`.** Resolution: the page never fetches. It asks the service worker (message channel) for the module bytes; the SW (own context, own CSP, no CSP header on `sw.js`) serves them from its cache, fetching only its fixed precache list at install. The test asserts a page `fetch` is blocked. Honest limit: the SW is the only network-capable code and is same-origin and auditable (`src/sw.ts`); a host that sends a CSP header on `sw.js` with `connect-src 'none'` would break the first install, so hosting must not do that (note for W12).
2. **No browser WASI package needed**: a 90-line shim was enough (no new dependency). The module ran without any filesystem import.
3. **Size remains the main risk** (W03 section 7): ~20 MB gzip first download. Not addressed here. Next levers: brotli (static host, likely 15-30 percent smaller than gzip), `wasm-opt -Oz`, investigate the 36.7 MB data segment (ICU) and a FoundationEssentials-only core. The service worker caches the decoded 54 MB; storage quota on a normal desktop profile is not a concern, but private windows may refuse it (not tested).
4. The SW reads the whole module into memory to post it to the page (two 54 MB copies transiently). Acceptable on desktop; consider streaming a compiled `WebAssembly.Module` (structured-cloneable to the page is not possible from a SW) or a dedicated Worker hosting the core if memory matters (W12).
5. After Delete all data the app shows a static "Everything was deleted" screen; restarting needs a network visit (the SW and caches are gone by design). The screen says so.
6. Not done (outside W04 scope): icons beyond one SVG (PNG sizes needed for installability on some browsers), axe/zoom/keyboard suites (W11), `plan.approve` UI wiring (W06), update flow for a new SW version (the cache name is content-versioned; prompt-to-reload UI is not built).
7. Local verification limits: no Swift toolchain or Chromium download was available in the development sandbox (download host blocked), so the browser test ran only in CI; typecheck and build were run locally.

## 4. How to run
```
cd platforms/web/app && npm ci
OMP_WASM=<path>/omp-web-wasm.wasm npm run build     # dist/
npx playwright install chromium && npm test          # serves dist/ on 127.0.0.1:4173
```
