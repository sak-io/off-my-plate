# platforms/

One folder per platform. Each is a separate codebase with its own UI, storage and packaging; **all of them share the one Swift core in `../core`** (the safety gate, planner, independent validator, plan lifecycle and services, with their tests). Safety logic is never copied into a platform.

| Folder | Platforms | Status |
|---|---|---|
| `ios/` | iPhone and iPad (iOS 18+). `ios/App` = XcodeGen project (app, share extension, UI tests); `ios/Apple` = Apple-only Swift package (SwiftData, speech, design system, screens) | built (v1) |
| `web/` | Windows, macOS and Linux desktops in a browser, installed as an offline PWA; the Swift core compiled to WebAssembly | proposed: `docs/windows/plan.md` (tasks W01-W12) |
| `linux/` | Raspberry Pi and other Linux/Unix machines | planned: `platforms/linux/README.md` |

Rules (enforced by `scripts/lint-*.sh`, which scan `core/` and `platforms/`):
1. A platform may depend on `core`; `core` never depends on a platform, and platforms never depend on each other.
2. Nothing in any platform talks to a network (ADR 0002). Each platform has its own proof (iOS: lint + network-denial UI test; web: Content-Security-Policy + browser test).
3. Approval of a plan needs an explicit user action on every platform (`UserConfirmation` is created in one reviewed file per platform; the safety lint and CODEOWNERS list those files).
4. New platform = new folder here + a CI workflow + a row in this table + a docs page in `docs/platforms/`.
