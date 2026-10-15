# ADR 0006: Generate the Xcode project with XcodeGen

- **Status:** Accepted (architect; tech §3 says "Xcode, SwiftPM for modules" and does not cover project files)
- **Date:** 2026-10-12

## Context
The app needs an app target, a share extension (App Group entitlement), a UI test target and signing settings. Hand-edited `.pbxproj` files break under parallel agents and can't be reviewed. SwiftPM alone can't produce an app with an app extension.

## Decision
Commit `App/project.yml` (XcodeGen) and git-ignore `*.xcodeproj`. Developers and CI run `xcodegen generate` (version pinned in `App/.xcodegen-version`; installed with `brew install xcodegen` or `mint`). Targets contain only composition-root code. Everything else lives in the packages. Signing team and bundle-ID prefix come from a git-ignored `App/Config/Local.xcconfig`; a `Local.xcconfig.example` is committed.

## Alternatives considered
1. Tuist. Rejected: more powerful but heavier (its own CLI, caching, Swift manifests). That's more than one app and one extension need.
2. A committed `.xcodeproj`. Rejected: merge conflicts and unreviewable diffs.

## Consequences
- The owner needs `brew install xcodegen` once.
- `project.yml` is small and reviewable. Agents on Linux can edit it but can't validate it, so validation happens on the Mac/CI.
