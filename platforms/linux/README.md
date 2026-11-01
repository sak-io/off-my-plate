# platforms/linux (planned, nothing built)

Target: Raspberry Pi (64-bit Raspberry Pi OS) and other Linux/Unix machines. Two routes are possible; both reuse `core` unchanged. Not decided; see `docs/platforms/linux-and-raspberry-pi.md`.

1. **Browser route (no code here):** run the `platforms/web` PWA in Chromium on the Pi (window or kiosk). Needs only the web build.
2. **Native route (this folder):** a Swift program built with `swift build` on Linux (x86_64 and aarch64) using `core` directly, with a terminal or GTK front end and file-based storage.

First step either way: prove `core` builds and passes its tests on Linux arm64 in CI (task L01).
