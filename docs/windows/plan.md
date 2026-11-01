# Windows version: plan (proposal, nothing built yet)

**Approach:** the same Swift core, compiled to WebAssembly, under a new offline web app (PWA) that installs from Edge or Chrome on Windows. See `docs/adr/0016-windows-via-wasm-core-and-offline-web-app.md`.

## Why this approach
- One copy of the safety logic and its tests (gate, planner, independent validator, 500-household safety suite). No second implementation to keep in sync.
- No Windows code-signing certificate or Store account needed; a PWA installs from the browser. It also runs in Safari/Chrome on the owner's macOS Monterey Mac.
- CI for a web app runs on cheap Linux runners (a few minutes), not the slow macOS runners.

## What carries over, what is new
| Carries over unchanged | New work |
|---|---|
| `OMPDomain`, `OMPSafetyCheck`, `OMPRecipes`, `OMPServices` and all their tests | Wasm build of the core; seed content embedded as generated Swift (no `Bundle`) |
| Copy catalogue (`docs/design/copy.md`), design docs, acceptance criteria | `OMPWeb` JSON facade (the only door to the core, incl. approvals) |
| Notes parser, voice-text parser (text only) | Web UI: ~20 screens in TypeScript; local storage in the browser; PWA/offline |
| Lints and the safety suite | Browser tests: accessibility (axe), keyboard, 200% zoom, no-network, offline |

## What is different on the web (owner-visible)
- No on-device voice input (browser speech recognition can use a server). Typing and chips only.
- No Notes share sheet: import by pasting text or choosing a file.
- Data lives in the browser profile on that PC. Clearing site data, or a different browser or profile, means a fresh start; there is no backup or sync (same stance as v1: no cloud).
- "Delete all data" clears the browser's stored data and caches for the app.

## Gate first: spike (W01)
Build the core for Wasm in CI and run the unit and safety suites under a Wasm runtime. If that fails, stop and re-plan before spending on UI.

## Tasks (board cards W01-W12, `work/tasks/`)
| ID | Task | Tier |
|---|---|---|
| W01 | Spike: Core builds and its tests pass on WebAssembly in CI | N |
| W02 | Seed content embedded as generated Swift for the Wasm build, with a drift check | N |
| W03 | `OMPWeb` JSON facade incl. the single approval bridge; lint allow-list and CODEOWNERS updated | **S** |
| W04 | Web app skeleton: TypeScript build, local storage, PWA shell, CSP, Delete all data | N |
| W05 | Onboarding and mandatory safety screens | **S** |
| W06 | Plan screens and explicit approval | **S** |
| W07 | Pantry and Mark cooked (typed input) | N |
| W08 | Shopping list and Notes import by paste/file | N |
| W09 | Household, learning, settings, disclaimer | N |
| W10 | Accessibility pass: axe, keyboard, zoom, dark mode, reduced motion | N |
| W11 | Privacy guarantees: CSP, network-denial browser test, offline test, web lint | N |
| W12 | Windows release: install guide, hosting, manual Windows checklist | N |

Rough size: about the size of the iPhone app layer (T19-T29), but verified on fast Linux CI.

## Decisions needed from the owner
1. **Approve the approach** (Wasm core + offline web app) over a native Windows app. Native costs more and needs a signing certificate.
2. **Web dependencies:** allow dev-time npm tools (bundler, test runner, axe-core) with the shipped app having zero runtime dependencies? (Recommended.) Or hand-written, tool-free.
3. **Hosting:** GitHub Pages (free, needs the repo public, already is) or a zip you open locally.
4. **Voice on web:** off (recommended), or opt-in with a clear warning.
5. Same open product decisions as v1 still apply (recipe/allergen sign-off, Malayalam keywords, etc.).
