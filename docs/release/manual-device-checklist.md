# Manual device checklist (plan section 10; run before every TestFlight build)

Run on a real iPhone (ideally iPhone 12-class, current iOS 18+) with the TestFlight build. All steps are **owner-only** (they need a physical device). Record results in the table at the end; attach notes for any failure and do not upload to testers until all are Pass.

1. **Real Notes share.** In Apple Notes, select a shopping/pantry note, Share, choose OffMyPlate. Open the app: the text appears as an import proposal to confirm; nothing is added silently.
2. **Speech, offline, en-IN.** Settings: language/region set so en-IN dictation is available; turn on Airplane Mode. Hold the mic and say "add two kilos of rice". It is recognised on device and parsed. If the device cannot do on-device recognition the app shows the unavailable message (C-135) and typing still works.
3. **VoiceOver pass.** Complete onboarding, safety screen, approve a plan, mark cooked, shopping list. Every control is announced with a label; the safety notice is read; no trapped focus.
4. **Reduce Motion.** Settings > Accessibility > Motion > Reduce Motion on: no large animations; flows still work.
5. **Performance.** Cold start to interactive under 1.5 s; generating a week plan under 2 s (iPhone 12-class). Record times (median of 3).
6. **Data Protection.** Add a household member and a pantry item. Lock the device and wait 1 minute, then unlock and reopen the app: the data is intact. Then, with the device connected to a Mac, confirm the store and its -wal and -shm files report Complete protection (Xcode > Devices > app container, or a debug build that logs `.protectionKey` for each file). Expected: all three show `complete`; any other value is a Fail.
7. **Delete all data.** Settings > Delete all data. Confirm: household, plan, pantry, shopping list, and any pending share-inbox items are gone; relaunch shows onboarding; no leftover Notes-shared text.
8. **Malayalam names.** Add a household member and a pantry item with Malayalam text including ZWJ/ZWNJ (for example "ക്ക", "ന്‍"). They display, save, search and survive relaunch without being split or dropped.
9. **No network.** With a network proxy or Airplane Mode, confirm all of the above behave the same (no network is ever needed).
10. **Icon and name.** The app icon is present (tracked from T02 review) and the display name is "OffMyPlate".

| Step | Device / iOS | Date | Result | Notes |
|---|---|---|---|---|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |
| 4 | | | | |
| 5 | | | | |
| 6 | | | | |
| 7 | | | | |
| 8 | | | | |
| 9 | | | | |
| 10 | | | | |
