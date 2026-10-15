# T29 review round 1 (light, tier N)
CI-uncatchable checks done; self-test run locally 7/7 (runs via check-core.sh glob scripts/tests/test-*.sh, so Linux CI covers it).

- [MAJOR] docs/release/data-map.md "What the app does not do": "iCloud/iTunes device backups follow the user's own OS settings" hides that the SwiftData store (allergies, children's names/age bands) and the share inbox are NOT excluded from backups (security audit M1; spec G6/ADR 0015 relies on backups). Table says "Leaves device? No" for health-adjacent data. State honestly: included in encrypted iCloud/iTunes device backups, not excluded, not readable by us; add to Open items for G4 reviewer (or exclude from backup and update). Also qualify privacy-nutrition-label "never leaves the device" with the backup note.
- [MINOR] release-readiness.sh accepts impossible dates (Date: 2026-99-99) and a trailing-nothing reviewer; tighten to a real month/day (01-12, 01-31). Fails closed on missing reviewer, unticked, [X]/[x], missing file (exit 2), empty sheet, draft lines.
- [MINOR] Draft-line grep is case-sensitive and only `- Review: draft`; relies on summary + check-seed-review.sh equality. Acceptable; consider -i and tolerate leading spaces.
- [MINOR] C-137 mismatch: Info.plist ("Speech stays on this device.") matches the copy.md note and ADR 0012, but docs/design/copy.md row C-137 still has the old sentence. Update copy.md row to the shipped string.
- [MINOR] manual-device-checklist step 6 is garbled ("Open the share sheet from Notes while locked is not possible"); rewrite as a clear expected result.
- [NIT] runbook step 1 "owner has merged the PR" precedes the OWNER build steps; fine. Bundle ids, app group, ITSAppUsesNonExemptEncryption verified against Base.xcconfig/project.yml/Info.plist.
- [PRAISE] Required-reason API claim verified: grep of Packages/ and App/ finds no UserDefaults/AppStorage/SceneStorage, no creation/modification dates, no disk-space/uptime/stat; only attributesOfItem reading `.size` (InboxStorage) and writing protection attributes. Manifest comments accurate. Self-test proves fail-on-draft, fail-on-unsigned, pass-on-signed, --app-store both ways, committed content fails.

VERDICT: CHANGES REQUESTED (one MAJOR: honest backup statement in data map)
