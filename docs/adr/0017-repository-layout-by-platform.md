# ADR 0017: Repository layout by platform

Status: Accepted (owner request 2026-11: organise the repository for iOS and Windows now and Linux/Raspberry Pi later).

## Context
v1 had `Packages/Core`, `Packages/Apple` and `App/`: fine for one platform, ambiguous with three. Web (Windows) and Linux/Raspberry Pi are planned (ADR 0016, `docs/platforms/linux-and-raspberry-pi.md`).

## Decision
`core/` holds the platform-neutral Swift core; each platform lives under `platforms/<name>/` (`ios`, `web`, `linux`). A platform may depend on `core`; `core` never depends on a platform and platforms never depend on each other. Lints scan `core/` and `platforms/`.

## Consequences
- One-time path move (task R01), verified by the lint self-tests (same 70 cases) and full CI; older records keep old paths, with the mapping in `docs/architecture/repo-layout.md`.
- The safety lints' allow-lists name the new exact paths (approval files, gate, validator); CODEOWNERS follows.
- Each new platform adds its own approval-bridge file to the allow-list in its own reviewed change.
