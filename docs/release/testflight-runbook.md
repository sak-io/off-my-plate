# TestFlight runbook

Every step marked **OWNER** needs the owner's Apple account or physical hands; agents never hold signing material. Never commit certificates, profiles, keys or `Local.xcconfig`.

## Identifiers
- App bundle ID `app.offmyplate.OffMyPlate`; Share Extension `app.offmyplate.OffMyPlate.Share`; App Group `group.app.offmyplate`.
- These come from `OMP_BUNDLE_ID_PREFIX = app.offmyplate` and `OMP_APP_GROUP_ID` in `App/Config/Base.xcconfig`. The Apple Developer team ID goes in the git-ignored `App/Config/Local.xcconfig` (copy `Local.xcconfig.example`).

## Before the first upload
1. **OWNER** Enrol in the Apple Developer Program; note the team ID.
2. **OWNER** In the developer portal create the two App IDs above, the App Group, and enable App Groups on both IDs.
3. **OWNER** In App Store Connect create the app record (name OffMyPlate, bundle ID above).
4. **OWNER** Create `App/Config/Local.xcconfig` with your team ID (stays on your machine).
5. Agent/anyone: confirm the app icon exists (T02 follow-up).

## Every build
1. Ensure CI is green on the session branch and the owner has merged the PR.
2. Run `scripts/release-readiness.sh`. It must print `OK`. It fails until all seed recipes are signed off (G1) and the restriction/keyword definitions are signed off (R4/G4) in `docs/content/restriction-signoff.md`. **OWNER** does those sign-offs.
3. Regenerate the project (`xcodegen generate` in `App/`), bump `CURRENT_PROJECT_VERSION` (and `MARKETING_VERSION` for a new version).
4. **OWNER** Run `docs/release/manual-device-checklist.md` on a real device (a debug build is fine for steps that do not need TestFlight) and record results.
5. **OWNER** In Xcode: select "Any iOS Device (arm64)", Product > Archive.
6. **OWNER** Organizer > Distribute App > App Store Connect > Upload (automatic signing with your team).
7. **OWNER** In App Store Connect > TestFlight: wait for processing, answer export compliance (already declared non-exempt = false), add the build to an **Internal Testing** group (up to 100 App Store Connect users; no Apple review).
8. **OWNER** Testers install via TestFlight; they are told the allergen disclaimer is draft guidance only.

## Before any App Store release (not needed for TestFlight beta)
- **OWNER** G4: legal/privacy reviewer approves privacy policy, `data-map.md` and disclaimer; dietitian spot-checks allergen tags. Tick the App Store lines in `docs/content/restriction-signoff.md`, then run `scripts/release-readiness.sh --app-store`.
- **OWNER** Host the privacy policy URL; fill App Privacy answers from `privacy-nutrition-label.md`.
- External TestFlight testers need a Beta App Review by Apple.
