# Status

**Phase:** Kickoff, step 3 (build) — 16 of 30 tasks merged; app-screen tasks on hold until macOS CI works
**Branch:** `claude/build-v1`

## Owner decisions at kickoff (2026-10-12)

1. **Build environment:** both the owner's Mac (Xcode) and a macOS GitHub Actions runner (added after the plan is approved). The cloud session builds and tests only the pure-Swift core.
2. **v1 scope (thin first version):** three-question onboarding with the mandatory safety gate; deterministic planner on ~30 seed recipes for one cuisine; plan approval; manual + voice pantry; shopping list; Apple Notes import via the Share Extension. **Deferred:** photo/PDF AI (guidance import, fridge recognition), CloudKit family sharing, BYOK, subscription/StoreKit, store carts and ordering.
3. **First cuisine:** Indian home cooking, with a **Kerala focus** (owner, 2026-10-13: "we are from Kerala and will be using the app for more Kerala dishes"). Seed ingredients (T05) and the 30 seed recipes (T06) prioritise Kerala dishes; onboarding offers a Kerala cuisine chip.
6. **Coconut:** not an allergen and not a tree nut (owner, 2026-10-13). No coconut chip on the safety screen.
4. **Autonomy:** 3 since 2026-10-12. The owner said "Go ahead and build it. Don't need my approval" for the plan; the owner still merges the final pull request.
5. **Team:** lean (starter + architect + qa-engineer) plus ux-designer. GitHub handle for `--owner`: to be confirmed.

## Done
- UX design (`docs/design/`) and architecture plan, 15 ADRs and 30-task breakdown (`docs/architecture/`, `docs/adr/`). Owner waived plan approval; recommendations R1–R9 apply as defaults.
- Spec approved by owner ("AGREED", 2026-10-12): `docs/specs/offmyplate-v1.md`. All gap defaults G1–G12 accepted.

- T01 foundation merged; both CI jobs green on 0884abe (Linux Swift 6.2, macOS Xcode 26.3 / Swift 6.2.4). T01 lint follow-up merged.
- T02 app walking skeleton merged (d75f9ec): CI green before merge, incl. app build and UI tests on iPhone and iPad simulators.
- T03 domain contracts, T07 units, T08 safety gate, T04 seed loader merged (CI green on both platforms before merge).
- T13 plan lifecycle, T17 learner, T09 plan validator, T05 ingredients (184, Kerala staples), T14 pantry/shopping math, T06 30 seed recipes (26 Kerala), T10 planner core merged (CI green on both platforms; combined branch green at a1a4ac4).
- T15 Notes parser, T20 SwiftData persistence (macOS CI green), T11 planner scoring/editing merged.
- T21 app shell: written (feat/t21), Linux green; waiting for macOS CI. T16 voice/safety text: written, in review.
- Tracked review follow-ups: `.autocraft/work/tracked.md`.

Process note: task branches are pushed as `claude/ci-tNN` so CI runs before merge (deviation from session-branch mode). The git proxy does not allow deleting remote branches; the owner can delete `claude/ci-*` branches on GitHub.

## Next
- Build T01–T30 per `docs/architecture/tasks.md`. Verification is GitHub Actions CI (no local Swift toolchain: download.swift.org is blocked).

## macOS CI unavailable (2026-10-13)
GitHub refuses to start macOS jobs: "recent account payments have failed or your spending limit needs to be increased" (Billing & plans). Owner decision: until fixed, merge core (pure-Swift `Packages/Core`) tasks when Linux CI is green; hold all app/screen tasks (Packages/Apple, App/) until macOS CI works. T11 was merged on Linux-green only (its previous revision 3fe2e5a was green on macOS too).

## Usage budget (owner decision, 2026-10-13)
At most 2 agents at a time; reviewers on Sonnet; short briefs; one review round for small non-safety tasks. Recorded in `.autocraft/custom/team-rules.md` and `.autocraft/config.yml`.

## Owner to-dos (non-blocking; defaults applied)
- R4 restriction definitions and G1 recipe/allergen sign-off (before beta).
- R6 bundle ID / App Group / team / Xcode version (defaults: `app.offmyplate.OffMyPlate`, `group.app.offmyplate`, team in git-ignored `Local.xcconfig`, Xcode 26).
- R3 make sure GitHub Actions is enabled for the repo (macOS minutes cost 10× on private repos).
- R2 (optional) allow download.swift.org in the environment's network settings.
