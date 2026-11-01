# Repo map (read this instead of exploring)
Layout: `core/` is shared by every platform; each platform is a folder under `platforms/` (`ios`, later `web`, `linux`). Older docs use the old paths `Packages/Core`, `Packages/Apple`, `App/`: see `docs/architecture/repo-layout.md`.
- `core` (pure Swift, Linux-testable): OMPDomain (types, planner, lifecycle), OMPSafetyCheck (independent validator), OMPRecipes (seed data/loader), OMPServices (use cases, in-memory repos).
- `platforms/ios/Apple`: OMPData (SwiftData), OMPCapture (voice/camera adapters), OMPUI (design system), OMPFeatures (screens, AppModel).
- `platforms/ios/App/`: app target, Share Extension, UI tests (XcodeGen `project.yml`).
- Docs: `docs/specs/offmyplate-v1.md` (ACs), `docs/architecture/{plan,tasks}.md`, `docs/adr/`, `docs/design/` (flows, screens, copy). Review follow-ups: `.autocraft/work/tracked.md`.
- Verify: CI workflows `core-linux` (Swift 6.2, lints, tests, safety suite) and `apple-macos` (Xcode 26, simulators). Locally: `scripts/check-core.sh [--lint-only]`.
- Lints that bite: `scripts/lint-core-imports.sh`, `lint-no-network.sh`, `lint-safety.sh` (only SafetyGate/clearance may unblock; reviewed exceptions in `unblock_allowed`).
- Branches: integration `claude/build-v1`; task branches `claude/ci-tNN`; batch branch `claude/ci-batch-N` for batched CI.
