# Status

**Phase:** Kickoff, step 3 (build) - see `work/BOARD.md`
**Branch:** `claude/build-v1`

## Owner decisions at kickoff (2026-10-12)

1. **Build environment:** both the owner's Mac (Xcode) and a macOS GitHub Actions runner (added after the plan is approved). The cloud session builds and tests only the pure-Swift core.
2. **v1 scope (thin first version):** three-question onboarding with the mandatory safety gate; deterministic planner on ~30 seed recipes for one cuisine; plan approval; manual + voice pantry; shopping list; Apple Notes import via the Share Extension. **Deferred:** photo/PDF AI (guidance import, fridge recognition), CloudKit family sharing, BYOK, subscription/StoreKit, store carts and ordering.
3. **First cuisine:** Indian home cooking, with a **Kerala focus** (owner, 2026-10-13: "we are from Kerala and will be using the app for more Kerala dishes"). Seed ingredients (T05) and the 30 seed recipes (T06) prioritise Kerala dishes; onboarding offers a Kerala cuisine chip.
6. **Coconut:** not an allergen and not a tree nut (owner, 2026-10-13). No coconut chip on the safety screen.
4. **Autonomy:** 3 since 2026-10-12. The owner said "Go ahead and build it. Don't need my approval" for the plan; the owner still merges the final pull request.
5. **Team:** lean (starter + architect + qa-engineer) plus ux-designer. GitHub handle for `--owner`: to be confirmed.

## Live status
**Source of truth is `work/BOARD.md`** (generated from `work/status/*.json`; protocol in `AGENTS.md`). Any AI system or human picks only `not_started` tasks (`python3 scripts/board.py next`).

Summary (2026-10-14): 16 of 30 merged; T12, T16, T18, T21 are in review on batch branch `claude/ci-batch-1` (Linux CI green, macOS CI being fixed); T19 has partial work on `wip/T19`; T22-T30 not started.

## Process notes
- GitHub Actions works again (repo is public). CI is batched: several finished tasks go on one `claude/ci-batch-N` branch per CI cycle.
- Task branches are pushed as `claude/ci-*` so CI runs before merge. The git proxy cannot delete remote branches; the owner can delete merged `claude/ci-*` and `wip/*` branches on GitHub.
- Review follow-ups: `.autocraft/work/tracked.md`.

## Usage budget (owner decision, 2026-10-13)
At most 2 agents at a time; reviewers on Sonnet; short briefs; one review round for small non-safety tasks. Recorded in `.autocraft/custom/team-rules.md` and `.autocraft/config.yml`.

## Owner to-dos (non-blocking; defaults applied)
- R4 restriction definitions and G1 recipe/allergen sign-off (before beta).
- R6 bundle ID / App Group / team / Xcode version (defaults: `app.offmyplate.OffMyPlate`, `group.app.offmyplate`, team in git-ignored `Local.xcconfig`, Xcode 26).
- R2 (optional) allow download.swift.org in the environment's network settings.
