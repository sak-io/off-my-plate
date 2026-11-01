## Tasks

### R01 [repo] Repository layout by platform. Linux + macOS
- **Goal:** `Packages/Core` -> `core`, `Packages/Apple` -> `platforms/ios/Apple`, `App` -> `platforms/ios/App`; lints, fixtures, CI, CODEOWNERS, XcodeGen paths and current docs updated; ADR 0017; `platforms/README.md` and `docs/architecture/repo-layout.md` (old -> new map); placeholders for `platforms/web` and `platforms/linux`.
- **Depends on:** none. **ACs:** no behaviour change; all lint self-tests keep their count (70) and pass; every CI job green.
- **Tests:** the lint self-tests prove no safety lint was weakened; full CI incl. iPhone and iPad.

### L01 [spike] Core builds and its tests pass on Linux arm64 (Raspberry Pi 64-bit). Linux
- **Goal:** a CI job on a GitHub arm64 Linux runner (ubuntu-24.04-arm) builds `core` with Swift 6.2 and runs all tests including the safety suite; record timings.
- **Depends on:** none. **ACs:** same results as x86_64 (determinism).
- **Tests:** the existing suites, unchanged.

### L02 [decision] Linux and Raspberry Pi delivery: browser kiosk or native. Linux
- **Goal:** decide with the owner, using the Pi's real use (screen, keyboard, voice) and the web app's state; write the result into `docs/platforms/linux-and-raspberry-pi.md`.
- **Depends on:** L01, W12. **ACs:** none (decision record).
- **Tests:** none.
