# platforms/web (approved, W01 spike first)

Windows (and macOS, Linux) in a browser: the Swift core compiled to WebAssembly under an offline-first web app, installable as a PWA. Plan, decisions needed and tasks W01-W12: `docs/windows/plan.md`. ADR: `docs/adr/0016-windows-via-wasm-core-and-offline-web-app.md`.

Contents:
- `facade/`: the `OMPWeb` Swift target (JSON in, JSON out) over `core`, including the single approval-bridge file.
- `app/`: the TypeScript web app (no runtime dependencies), service worker, Playwright tests (W04). Build: `cd app && npm ci && OMP_WASM=<omp-web-wasm.wasm> npm run build && npm test`. CI: `.github/workflows/web-app.yml`. Findings: `docs/windows/w04-report.md`.
