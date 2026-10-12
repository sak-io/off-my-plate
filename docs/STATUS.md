# Status

**Phase:** Kickoff, step 1 (spec)
**Branch:** `claude/build-v1`

## Owner decisions at kickoff (2026-10-12)

1. **Build environment:** both the owner's Mac (Xcode) and a macOS GitHub Actions runner (added after the plan is approved). The cloud session builds and tests only the pure-Swift core.
2. **v1 scope (thin first version):** three-question onboarding with the mandatory safety gate; deterministic planner on ~30 seed recipes for one cuisine; plan approval; manual + voice pantry; shopping list; Apple Notes import via the Share Extension. **Deferred:** photo/PDF AI (guidance import, fridge recognition), CloudKit family sharing, BYOK, subscription/StoreKit, store carts and ordering.
3. **First cuisine:** Indian home cooking.
4. **Autonomy:** 2 (owner approves spec, plan and the final pull request).
5. **Team:** lean (starter + architect + qa-engineer) plus ux-designer. GitHub handle for `--owner`: to be confirmed.

## Next
- Requirements analyst: ingest the source documents into `docs/specs/`, with gaps and recommended defaults, for owner approval.
