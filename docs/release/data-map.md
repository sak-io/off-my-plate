# Data map (spec NFR Privacy/Children; ADR 0002, 0014; G4 review pending)

Status: DRAFT for the G4 legal/privacy reviewer. The app sends nothing off the device itself, BUT device backups are a gap (see "Device backups").

| Data | Examples | Where stored | Protection | Leaves device? | Deleted by "Delete all data" |
|---|---|---|---|---|---|
| Household | member count, optional first names, optional age band, children flag | SwiftData store in the app container | iOS Data Protection `complete` (store, -wal, -shm) | No | Yes |
| Safety rules | allergies and dietary restrictions per member (health-adjacent) | same store | same | No | Yes |
| Plans, approvals, pantry, shopping list, cook log, learned preferences | | same store | same | No | Yes |
| Share inbox | text shared from Notes or other apps | App Group container (`group.app.offmyplate`), temporary until imported | `completeFileProtection` | No | Yes |
| On-device counters | time to first plan, prompts shown/answered (ADR 0014) | local only (none implemented as of 2026-10-14) | app container | No | Yes |
| Voice | microphone audio, transcript | Not stored. Recognised on device (`requiresOnDeviceRecognition = true`, ADR 0012) and discarded after parsing | n/a | No | n/a |
| Crash/stability reports | Apple TestFlight / App Store Connect only, opt-in at OS level | Apple | | Only via Apple, by the user's OS setting | n/a |

## What the app does not do
- No account, sign-in, server, backend or network call (lint `lint-no-network.sh` enforces this in code).
- No third-party SDK, analytics, advertising identifier or tracking (`NSPrivacyTracking` = false, no tracking domains).
- No camera, contacts, location, Reminders, Calendar or Photos access. Permissions: microphone and speech recognition only, requested just in time.
- No cloud sync in v1 (ADR 0015); iCloud/iTunes device backups follow the user's own OS settings.

## Children
Children are data subjects, never users: the app is operated by the parent. No name or birth date is required; only an optional name and an optional age band are stored, on the device. Nothing about a child is sent anywhere or tied to an analytics identifier. Do not market in the Kids category (the app is for parents).

## Device backups (OPEN OWNER DECISION)
Today the SwiftData store (allergies, children's optional names and age bands, pantry, plans) and the App Group share inbox are **included in iCloud and iTunes/Finder device backups**: neither is excluded (security audit M1, `.autocraft/work/security/audit-2026-10-14.md`). So "never leaves the device" is true of the app, not of the user's own OS backup, and "Delete all data" cannot remove copies already in a backup.
- Option A: set `isExcludedFromBackup` on the store and the inbox. Tradeoff: data is lost on a device restore or a move to a new phone.
- Option B: keep backups and disclose it in the privacy copy and policy.
Owner decides (recommended default: A for the safety/children data, since delete-all is a promise we make); also an open G4 item for the privacy reviewer.

## Open items
- G4: decide the device-backup question above and make the policy wording match.
- G4: a qualified privacy reviewer must approve this map, the privacy policy and the disclaimer before any App Store release (TestFlight beta may proceed).
- App Store Connect needs a privacy policy URL (owner to host; the policy can state "no data collected").
