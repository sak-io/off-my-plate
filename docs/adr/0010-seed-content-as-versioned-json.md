# ADR 0010: Seed recipes and ingredient taxonomy as versioned JSON resources

- **Status:** Accepted (owner: tech §9, kickoff #2/#3, spec G1, A2, A3; format by architect)
- **Date:** 2026-10-12

## Context
About 30 Indian recipes and about 150 ingredients ship in the bundle. The safety guarantee is only as good as the tags. G1: the team drafts the content, the owner signs off, provenance is recorded per recipe, and doubtful items are tagged conservatively.

## Decision
- `Packages/Core/Sources/OMPRecipes/Resources/seed/`: `catalog.json` (food tags, restrictions -> excluded tags, aisles), `ingredients.json`, `recipes.json`. Each file has `schemaVersion` and a shared `contentVersion`. They are loaded with `Bundle.module` (works on Linux).
- Ingredients carry `tags`, `mayContain` and `tagStatus: verified|unverified`. Recipes do **not** carry authoritative allergens. They carry `declaredTags` (the author's statement), and a test requires `declaredTags == derived(ingredients)`. That catches mistakes in either place.
- `provenance` per recipe (author, original/adapted, source note) and `review: {status: draft|signedOff, by?, date?}`. The release-readiness check (not dev CI) fails while any recipe isn't `signedOff`. That is the G1/G4 gate.
- `scripts/seed-review-sheet` (a Swift executable target) generates a markdown sheet of recipe -> ingredients -> tags for the owner's sign-off.

## Alternatives considered
1. SwiftData-preloaded store. Rejected: it can't be validated on Linux, it is a binary in git, and it is hard to review.
2. Swift literals in code. Rejected: content edits would show up as code diffs, and non-engineers can't review them.
3. CSV. Rejected: nested ingredient lists are awkward in CSV.

## Consequences
- The content is reviewable in pull requests. The validation tests are the first line of defence, and human sign-off is the second.
