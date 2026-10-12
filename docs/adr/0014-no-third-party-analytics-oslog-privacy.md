# ADR 0014: No third-party analytics or crash SDKs; OSLog with privacy; on-device counters

- **Status:** Accepted (owner: tech §11, §8.5 instrumentation; spec NFR Privacy/Analytics)
- **Date:** 2026-10-12

## Decision
- Crash and stability data come from Apple's TestFlight/App Store Connect reports only, which are opt-in at the OS level.
- `os.Logger` in the Apple layer, with every interpolated user value marked `privacy: .private`. The core does not log; it returns typed results.
- On-device counters (time to first plan; prompts shown, answered and skipped; proposals confirmed and dismissed) are stored locally, never transmitted, and wiped by "Delete all data".
- `PrivacyInfo.xcprivacy` declares no tracking and no collected data, plus the required-reason APIs used (for example `UserDefaults`, file timestamps).

## Alternatives considered
1. Sentry or Firebase Crashlytics. Rejected: they send data to a third party, which contradicts the owner's privacy stance and the NFR.

## Consequences
- Field diagnostics are thinner. The ≥99.5% crash-free target is measured from App Store Connect.
