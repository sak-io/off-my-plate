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

## Live status (2026-10-14)
**All 30 tasks are built and merged on `claude/build-v1`; CI green** (Linux Core, Swift packages, Release-hygiene, iPhone and iPad UI shards). Source of truth for task state is `work/BOARD.md`; protocol in `AGENTS.md`.

**v1 is feature-complete but NOT release-ready.** Release needs the owner items below (device checks, sign-offs, privacy decision, TestFlight upload). `scripts/release-readiness.sh` fails until the content sign-offs exist.

## Owner sign-offs and decisions needed
1. **G1 recipe / allergen sign-off and R4/G4 restriction definitions** - `docs/content/seed-review.md`, `docs/content/restriction-signoff.md` (script `scripts/release-readiness.sh` fails until signed). A dietitian spot-check and a privacy review are App-Store-only items.
2. **Backups (decision):** the SwiftData store and the share inbox are included in iCloud/iTunes backups today, so "Delete all data" cannot reach copies already in a backup. Option A: exclude both (`isExcludedFromBackup`; data lost on restore to a new phone). Option B: keep and disclose in the privacy policy. See `docs/release/data-map.md`.
3. **Accessibility audit waivers (batch 4):** Pantry, Shopping, Settings and Plan-draft audit tests record findings as expected failures; plus iPad/"Plan"-label exceptions. All live in `App/OffMyPlateUITests/AccessibilityAudit.swift`. Needs a person with Xcode's Accessibility Inspector, then delete every exception (tracked.md, T28 rows).
4. **Malayalam / Hindi safety keywords**, lunchbox child/teen band assumption, **Mark cooked deducts expired items first** (T14), "Clear checked items" wording (C-149), the Kerala cuisine chip (no copy yet), optional-name handling, two T19 defaults (key ingredients = first two non-optional lines; an imported item that matches the plan becomes its own "from Notes" row).
5. **App icon, bundle IDs / App Group / team ID** (placeholders in `Base.xcconfig`; team in git-ignored `Local.xcconfig`), privacy policy URL.
6. **Manual device checklist** (`docs/release/manual-device-checklist.md`): real Notes share, on-device speech offline (en-IN), VoiceOver, Reduce Motion, cold start < 1.5 s, Data Protection while locked, delete-all, Malayalam names.
7. **TestFlight upload** is a human step: `docs/release/testflight-runbook.md`.
8. Not done (tracked): portion steppers on the plan (needs a Core servings-edit service), iPad split view, AX5 and dark-mode audits per screen, Share Extension string catalogue, backup exclusion, xcodegen pin.

## Process notes
- CI is batched; UI tests build once and run as parallel shards. iPad shards run only on `main`, manual dispatch, or when the head commit message contains `[ipad]` (put it on the push you intend to merge).
- Task branches are pushed as `claude/ci-*` so CI runs before merge. The git proxy cannot delete remote branches: the owner can delete merged `claude/ci-*` and `wip/*` branches on GitHub.
- Review follow-ups: `.autocraft/work/tracked.md`. Security audit: `.autocraft/work/security/`.

## Usage budget (owner decision, 2026-10-13)
At most 2 agents at a time; reviewers on Sonnet; short briefs; one review round for small non-safety tasks. Recorded in `.autocraft/custom/team-rules.md` and `.autocraft/config.yml`.

## Owner to-dos (non-blocking; defaults applied)
- R4 restriction definitions and G1 recipe/allergen sign-off (before beta).
- R6 bundle ID / App Group / team / Xcode version (defaults: `app.offmyplate.OffMyPlate`, `group.app.offmyplate`, team in git-ignored `Local.xcconfig`, Xcode 26).
- R2 (optional) allow download.swift.org in the environment's network settings.
