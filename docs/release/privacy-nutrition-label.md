# App Store privacy "nutrition label" answers

For App Store Connect, App Privacy section. Source: `docs/release/data-map.md`, `PrivacyInfo.xcprivacy` (app and share extension).

| Question | Answer |
|---|---|
| Do you or your third-party partners collect data from this app? | **No** (the app never transmits data; note theuser's own iCloud/device backup may contain app data today, an open owner decision in `data-map.md` "Device backups", also an open G4 item; Apple's definition of "collect" means transmitting off-device) |
| Data types collected | None. Health-adjacent allergy/diet info and children's optional names stay on-device |
| Used for tracking? | **No** |
| Tracking domains | None |
| Third-party SDKs | None |
| Privacy policy URL | Required for App Store (owner to host); optional for TestFlight internal testing |
| Age rating / Kids category | Not in the Kids category; the app is for parents. Answer the age-rating questionnaire honestly (no mature content) |
| Export compliance | `ITSAppUsesNonExemptEncryption` = false (set in Info.plist; no custom cryptography, SHA-256 hashing only) |

## Privacy manifests
- `App/OffMyPlate/PrivacyInfo.xcprivacy` and `App/OffMyPlateShare/PrivacyInfo.xcprivacy`: no tracking, no collected data, no required-reason APIs used (audited 2026-10-14). Whoever adds `UserDefaults`, file timestamps, disk-space or boot-time APIs must add the matching `NSPrivacyAccessedAPITypes` entry (for example `UserDefaults` with reason `CA92.1`) in the same change.
- Purpose strings (UX copy C-136, C-137) are in `App/OffMyPlate/Info.plist`: microphone and speech recognition. They say speech stays on the device, matching ADR 0012. The Share Extension needs no purpose strings (text only, no sensor access).

## Owner-only
Entering these answers in App Store Connect and the final G4 approval are owner steps.
