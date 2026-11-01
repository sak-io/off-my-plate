# Linux, Unix and Raspberry Pi (plan, not started)

Goal (owner, later): run OffMyPlate on Linux and Unix machines such as a Raspberry Pi.

## What already helps
- `core` is Foundation-only and already builds and passes its tests on Linux x86_64 in CI (`core-linux.yml`, `swift:6.2-noble`).
- Swift 6.2 supports Linux on x86_64 and aarch64 (64-bit Raspberry Pi OS). GitHub offers free arm64 Linux runners for public repositories, so CI can prove it on the same CPU family as the Pi.

## Routes
| | Browser route | Native route |
|---|---|---|
| What | the `platforms/web` PWA in Chromium (window or kiosk) | a Swift program in `platforms/linux` using `core` |
| New code | none beyond the web app | new UI (terminal or GTK), file-based storage, packaging |
| Other Unix (FreeBSD, etc.) | works wherever a modern browser does | Swift on BSD is community-supported only |
| Offline / no network | CSP + browser test | lint + a no-network test |
| Effort | tiny, once web exists | medium |

Recommendation: start with the browser route (it reuses the web build and works on any Unix with a browser), and decide on a native app only if a headless or kiosk use case needs it.

## Tasks (board cards L01-L02)
- **L01** spike: `core` builds and its tests (incl. the safety suite) pass on Linux arm64 in CI.
- **L02** decision: browser kiosk or native, with the Pi's actual use (screen, keyboard, voice?) as input.

Voice on Linux: no on-device recogniser is part of the core; treat it like the web (off) until a local engine is chosen, so nothing leaves the machine.
