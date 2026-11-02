# W04 review, round 1 (head ca8a4d1, code 987beb2)

VERDICT: APPROVED

No BLOCKER or MAJOR. I did not run Playwright (CI reported it green; the "Playwright" step fails the job on non-zero rc). Typecheck/build not run locally either; review is by reading.

## Checked
- Zero runtime deps: package.json has only devDependencies, exact pins (playwright 1.49.1, @types/node 22.10.2, typescript 5.7.2); lockfile committed with integrity hashes; CI uses `npm ci --ignore-scripts`.
- CSP: default-src 'none', connect-src 'none', script/style/img self, base-uri/form-action none. No inline script/style. Page code has no fetch/XHR/WebSocket; only `sw.ts` fetches (precache list at install, plus same-origin WASM fallback). SW fetch handler ignores cross-origin and non-GET. E2E asserts page fetch is blocked.
- Delete all data: all IndexedDB DBs, all caches, local/sessionStorage, SW unregister, then re-instantiates Wasm (in-memory state dropped). E2E asserts dbs/caches/regs/localStorage are 0.
- No UserConfirmation or approve call anywhere in src; every core call goes through `makeCtx()`; `Core.call` requires ctx (no default).
- No skipped/disabled tests (no test.skip/fixme/only). E2E is meaningful: persistence across reload, offline reload, state restored, delete empties stores.
- XSS: no innerHTML/eval; all dynamic text via textContent, including core error messages.
- No secrets. `core/` untouched (0 files). Workflow: actions pinned by SHA, `contents: read`, persist-credentials false, trigger only on `claude/ci-w*` + dispatch with path filter, checksum-pinned Wasm SDK.

## MINOR / NIT (track in tracked.md)
- [MINOR] E2E does not assert in-memory state is cleared after Delete (e.g. no household after delete, or a fresh instance). The code does it; add a check when the restart path exists.
- [MINOR] CSP test only checks one same-origin fetch is blocked; consider recording `page.on("request")` to assert no cross-origin requests at all.
- [MINOR] `READ_ONLY` is a name-suffix regex deciding whether to persist; a future write op named `*.status`/`*.get` etc. would silently not persist. Prefer an explicit allow-list or have the facade flag mutating ops (revisit in W06).
- [MINOR] `op()` saves are not serialized; two overlapping state-changing ops could write snapshots out of order. Also an in-flight save could recreate the DB right after Delete. Chain saves through a promise queue and block ops once deleted.
- [MINOR] `onblocked` in deleteEverything resolves and counts the DB as wiped though deletion is deferred; the UI then claims deletion. Acceptable single-tab, note for W12.
- [NIT] Meta CSP cannot express frame-ancestors; set the header at the host (W12) along with a note that `sw.js` must not get a connect-src 'none' header (already in report).
- [NIT] `serve.mjs` duplicates the CSP string from index.html; derive one from the other to avoid drift.
- [NIT] `core.ts` accepts `args` typed Json but main passes `Record<string, any>`; fine for now.
