# Status

**Phase:** Kickoff, step 3 (build) — T01 in progress
**Branch:** `claude/build-v1`

## Owner decisions at kickoff (2026-10-12)

1. **Build environment:** both the owner's Mac (Xcode) and a macOS GitHub Actions runner (added after the plan is approved). The cloud session builds and tests only the pure-Swift core.
2. **v1 scope (thin first version):** three-question onboarding with the mandatory safety gate; deterministic planner on ~30 seed recipes for one cuisine; plan approval; manual + voice pantry; shopping list; Apple Notes import via the Share Extension. **Deferred:** photo/PDF AI (guidance import, fridge recognition), CloudKit family sharing, BYOK, subscription/StoreKit, store carts and ordering.
3. **First cuisine:** Indian home cooking.
4. **Autonomy:** 3 since 2026-10-12. The owner said "Go ahead and build it. Don't need my approval" for the plan; the owner still merges the final pull request.
5. **Team:** lean (starter + architect + qa-engineer) plus ux-designer. GitHub handle for `--owner`: to be confirmed.

## Done
- UX design (`docs/design/`) and architecture plan, 15 ADRs and 30-task breakdown (`docs/architecture/`, `docs/adr/`). Owner waived plan approval; recommendations R1–R9 apply as defaults.
- Spec approved by owner ("AGREED", 2026-10-12): `docs/specs/offmyplate-v1.md`. All gap defaults G1–G12 accepted.

## Next
- Build T01–T30 per `docs/architecture/tasks.md`. Verification is GitHub Actions CI (no local Swift toolchain: download.swift.org is blocked).

## Owner to-dos (non-blocking; defaults applied)
- R4 restriction definitions and G1 recipe/allergen sign-off (before beta).
- R6 bundle ID / App Group / team / Xcode version (defaults: `app.offmyplate.OffMyPlate`, `group.app.offmyplate`, team in git-ignored `Local.xcconfig`, Xcode 26).
- R3 make sure GitHub Actions is enabled for the repo (macOS minutes cost 10× on private repos).
- R2 (optional) allow download.swift.org in the environment's network settings.
