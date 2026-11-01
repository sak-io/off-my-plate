# Install OffMyPlate on your own iPad for testing (no paid Apple developer account)

For personal testing only. You re-sign the app with your own free Apple ID. It is **not** TestFlight and **not** for sharing with other people.

## What you need
- An iPad on iPadOS 18 or newer (yours is on the latest, which is fine).
- A computer (Windows or a Mac) with a USB cable for the iPad.
- Your Apple ID (free). Two-factor sign-in works.
- The unsigned app file from CI (below).

## 1. Get the app file (about 8 minutes of CI)
1. On GitHub open the repository > **Actions** > **apple-macos** > **Run workflow**.
2. Choose the branch (`claude/integration`), tick **build_ipa**, press **Run workflow**. Only the app build runs; the tests are skipped.
3. When it finishes open the run, scroll to **Artifacts**, download **OffMyPlate-unsigned-ipa** (a zip containing `OffMyPlate-unsigned.ipa`) and unzip it. Artifacts are kept 7 days.

## 2. Turn on Developer Mode on the iPad (once)
Settings > Privacy & Security > Developer Mode > On. The iPad restarts and asks you to confirm. (The option only appears after you have first connected the iPad to a computer with a sideloading tool.)

## 3. Install it with a sideloading tool (pick one)
These are third-party tools. I have not audited them and you give them your Apple ID, so download them only from their official sites and consider using a spare Apple ID. Check that the current version supports your computer's operating system before you start (older macOS versions such as Monterey may be unsupported by the newest releases).

**Sideloadly** (Windows or Mac; simplest): connect the iPad by USB and tap **Trust** on it; drag `OffMyPlate-unsigned.ipa` into Sideloadly; enter your Apple ID; press **Start**. It re-signs the app, gives it a unique bundle ID if needed, and installs it.

**AltStore** (Windows or Mac): install AltServer on the computer, install AltStore on the iPad from it, then open AltStore on the iPad > **My Apps** > **+** and pick the `.ipa` (send it to the iPad with AirDrop or Files). AltStore can refresh the app by itself while the iPad and computer are on the same Wi-Fi.

## 4. Trust the app and open it
Settings > General > VPN & Device Management > your Apple ID > **Trust**. Then open OffMyPlate.

## Limits of the free route (expect these)
- The app **stops opening after 7 days** until re-signed: repeat step 3 (AltStore can do this automatically). Your data stays on the iPad if you re-install over the top; deleting the app deletes the data.
- A free Apple ID allows only a few apps and App IDs per week. OffMyPlate uses two (the app and its share extension).
- The **Notes share extension may not work**: it passes data through an App Group that a free account may not be able to create. The rest of the app does not depend on it; Notes import is skipped if the group is missing.
- Voice input asks for microphone and speech permission on first use and runs on the device.
- Nothing in this build talks to a network; if the app misbehaves, note what you did and any message, and tell me.
