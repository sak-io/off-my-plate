# AGENTS.md - start here (any AI system or human)

This repo is built by many agents over time (Claude app/CLI, ChatGPT, Codex, Cursor, Grok, humans). The live task state is **files in git**, so everyone sees the same truth.

## 30-second protocol
1. Read `work/BOARD.md` (generated live status) and `work/CONTEXT.md` (repo map, how to verify).
2. Run `python3 scripts/board.py next` - it lists the **only** tasks you may take (`not_started` with satisfied dependencies). Never touch a task that is `claimed`, `in_review`, `merged` or `blocked`.
3. `python3 scripts/board.py claim <ID> --agent <your-name>` - this commits + pushes the claim; if the push loses the race it tells you to pick another. No shell? Edit `work/status/<ID>.json` (`state: "claimed"`, `owner`, `claimed_at`, `heartbeat_at`) and push it to `claude/build-v1` yourself.
4. Read `work/tasks/<ID>.md` (self-contained brief) plus `work/LESSONS.md` (CI pitfalls that already cost us rounds). Read only what the card names.
5. Work on branch `claude/ci-<id>` (lowercase). Push early and often - **CI is the only compiler/test runner** (no local Swift in the cloud; if you have Xcode/Swift locally, run `scripts/check-core.sh`).
6. Done: push, then `python3 scripts/board.py submit <ID> --agent <name> --branch <branch>` (state becomes `in_review`). A different agent/human reviews (tier S = full safety review; tier N = one light pass). Only the integrator runs `board.py merge <ID>` after CI is green.
7. Out of budget/time? `board.py release <ID> --wip-branch <branch> --note "what is left"`. Leases expire after 6h without `board.py heartbeat <ID> --agent <name>`; an expired claim is free again.

## Non-negotiable rules
- Nothing reaches `main` until the owner merges the PR. Never commit secrets. Never skip/disable a test or lint to get green.
- Safety is the product: see `docs/adr/` and `docs/technical-specification.md`. Tier S tasks touch the safety path - keep the independent validator, SafetyGate token and explicit approval intact.
- Source of truth: `docs/specs/offmyplate-v1.md`, `docs/architecture/`, `docs/design/`. Declare deviations in the PR/card note.
- Keep output small; do not re-read the whole docs tree. The card says what to read.

Tool-specific notes: Claude Code reads `CLAUDE.md` (which points here); Cursor/Codex/Copilot read this file; ChatGPT/Grok: paste this file + the card + `work/CONTEXT.md` as your brief, and ask the human to run git/CI.
