# ADR 0004: Module layout: a portable Core package plus an Apple package

- **Status:** Accepted. Module names are given by owner (tech §4.1); the split and two added modules are by the architect.
- **Date:** 2026-10-12

## Context
Tech §4.1 lists `OMPDomain`, `OMPData`, `OMPIntelligence`, `OMPCapture`, `OMPRecipes`, `OMPUI`, `OMPApp` and extension targets. It puts Notes parsing in `OMPCapture`, which depends on `OMPIntelligence`, and it has no module for the "Application Services (use cases)" layer drawn in tech §4. The safety logic, the parsers and the use cases all need to be tested on Linux.

## Decision
Two SwiftPM packages and one generated Xcode project:
- `Packages/Core` (Linux + Apple; Foundation only; no dependencies): `OMPDomain` (entities, units, safety gate, planner, plan lifecycle, pantry/shopping math, Facts/learning, prompt scheduler, rule-based parsers), `OMPSafetyCheck` (the independent hard-rule validator, tech §6.2), `OMPRecipes` (seed JSON + loader), `OMPServices` (**added**: use cases + repository protocols + in-memory repositories).
- `Packages/Apple` (iOS 18 / macOS 15): `OMPData` (SwiftData), `OMPCapture` (Speech capture only in v1), `OMPUI` (design system), `OMPFeatures` (**added**: screens + view models, so the app target stays a thin composition root).
- `App/` (XcodeGen, ADR 0006): `OffMyPlate` app target (composition root, navigation), `OffMyPlateShare` share extension, UI test target.
- **Deviation from tech §4.1:** the text and voice-grammar parsers live in `OMPDomain`, not `OMPCapture`. `OMPCapture` keeps only the Apple capture adapters. `OMPIntelligence` is deferred (ADR 0002).

## Alternatives considered
1. One package with `#if os(Linux)` target lists. Rejected: fragile manifest logic, and it is easy to leak Apple imports into core targets.
2. Everything in the Xcode project. Rejected: nothing would be testable on Linux, and project-file merge conflicts would block parallel work.
3. One module per feature screen. Rejected for v1: too many moving parts for about 15 screens.

## Consequences
- The Linux CI job builds `Packages/Core` only. A lint fails if a Core source imports anything other than `Foundation`.
- The share extension links only `OMPDomain` (parsers and the inbox format), so it can never reach planning or approval code.
