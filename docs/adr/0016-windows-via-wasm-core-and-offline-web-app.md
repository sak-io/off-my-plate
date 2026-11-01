# ADR 0016: Windows (and any desktop) via the Swift core compiled to WebAssembly plus an offline web app

Status: **Accepted** (owner approved 2026-11; see `docs/windows/plan.md`). W01 is the feasibility gate.

## Context
OffMyPlate v1 is an iOS/iPadOS app (SwiftUI, SwiftData, iOS 18). None of that runs on Windows. The owner asked for a real Windows version. The product's value is its safety-critical, deterministic core (`Packages/Core`: gate, planner, independent validator, lifecycle, services) and its 500-household safety suite. A second implementation of that logic in another language would double the safety surface and let the two drift apart.

## Decision (proposed)
1. Compile `Packages/Core` unchanged to WebAssembly (Swift 6.2 WebAssembly SDK) and run it in the browser.
2. Build a new web UI (TypeScript, no runtime dependencies) that talks to the core through a small JSON facade (`OMPWeb`), installable as a PWA on Windows (Edge or Chrome "Install app"), fully offline.
3. Keep the product promises: nothing leaves the device (Content-Security-Policy `connect-src 'none'`, no `fetch`/`XMLHttpRequest`/`WebSocket`/beacon, a network-denial browser test), data in the browser's local storage, "Delete all data" really clears it, explicit approval only from a user click.

## Why not a native Windows app
WinUI/.NET or similar would need the core re-implemented (or wrapped as a DLL through a C ABI), a Windows signing certificate or Store account to install it, and a second UI anyway. The web route reuses the exact core and tests, needs no signing, and also runs on macOS Monterey and Linux in a browser.

## Consequences
- The seed content (`Bundle.module` resources) is embedded as generated Swift for the Wasm build.
- `UserConfirmation` must still be created only from an explicit user action: the facade gets ONE approval-bridge file, added deliberately to the `lint-safety.sh` allow-list and CODEOWNERS.
- Voice input is off on the web (browser speech recognition can send audio to a server, which breaks the on-device promise). Notes import is by paste or file.
- A spike (W01) decides feasibility before any UI work: if the core does not build and pass its tests on Wasm, this ADR is withdrawn and the native route is re-planned.
