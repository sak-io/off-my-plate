# ADR 0009: Deterministic greedy planner with seeded tie-breaks

- **Status:** Accepted (owner: tech §6.1 pipeline, §1.3; selection method simplified by architect)
- **Date:** 2026-10-12

## Context
Tech §6.1 step 5 suggests greedy plus local search or a small ILP, mainly for nutrition targets. Nutrition is deferred in v1 and the library has about 30 recipes. AC-4.6 requires determinism, and plan generation must take under 2 s.

## Decision
Pipeline: Gather -> Expand slots -> Hard filter -> Score -> Greedy select (in date/slot order) -> Personalise servings -> Explain. Validation and persistence happen in `OMPServices`. Scores are a fixed weighted sum of named components (`pantryCoverage`, `expirySoon`, `cuisineAffinity`, `dislikePenalty`, `timeFit`, `varietyPenalty`, `recentlyCookedPenalty`, `favourite`). Ties are broken by a `SplitMix64` seeded from `(householdId, weekStart, revision)`, then by recipe id. Variety: no repeat within 3 days, relaxed per slot when no safe alternative exists (G5), with a reason attached. With no safe candidate the slot is empty with `.noSafeRecipe`.

## Alternatives considered
1. ILP/local search. Rejected for v1: no nutrition objective yet. Revisit with nutrition targets.
2. Unseeded randomness for "freshness". Rejected: breaks AC-4.6 and makes tests flaky. Re-roll gives freshness deterministically by excluding the current recipe.

## Consequences
- Weights are a single table, unit-tested by component.
- The explanation templates come from the top two positive components (AC-4.7).
