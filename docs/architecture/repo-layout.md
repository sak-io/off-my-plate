# Repository layout

```
core/                      shared Swift core, every platform uses it (safety gate, planner, validator, services, seed content)
platforms/
  ios/App/                 iPhone/iPad XcodeGen project: app, share extension, UI tests
  ios/Apple/               Apple-only Swift package: SwiftData, speech, design system, screens
  web/                     Windows/macOS/Linux browsers: Wasm core + web app (proposed)
  linux/                   Raspberry Pi / Linux native (planned)
docs/                      shared docs; docs/platforms/ and docs/windows/ per-platform plans; docs/release/ release material
scripts/                   shared lints, CI helpers and their self-tests (scripts/tests/)
work/                      agent-agnostic task board (AGENTS.md)
.github/                   workflows (core-linux.yml, apple-macos.yml, later web and linux-arm64)
```
See `platforms/README.md` for the rules between the folders.

## Move on 2026-11 (task R01): old path -> new path
| Before | Now |
|---|---|
| `Packages/Core` | `core` |
| `Packages/Apple` | `platforms/ios/Apple` |
| `App` | `platforms/ios/App` |

Older documents (ADRs, the v1 spec, `docs/architecture/plan.md` and `tasks.md`, the design docs, review notes, `work/tasks/T*.md`) still use the old paths because they record decisions as they were made. Read them through this table; current docs, scripts and CI use the new paths.
