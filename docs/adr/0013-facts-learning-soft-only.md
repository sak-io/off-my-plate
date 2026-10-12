# ADR 0013: Facts and learning are soft-only by construction

- **Status:** Accepted (owner: tech §5.2, §8.5; spec US-12, G10; mechanism by architect)
- **Date:** 2026-10-12

## Context
The app may learn preferences but must never create or change hard rules or safety status (AC-12.4).

## Decision
- Hard restrictions are a separate type, `Rule(kind: .hard)`. They can only be created by `SafetyService.confirmSafetyAnswer`, from the safety screen or Settings -> Household & safety.
- `FactLearner.update(facts:events:recipes:now:timeZone:) -> [Fact]` is pure (amended in T17: `recipes` is a `[RecipeID: RecipeTraits]` map of soft traits only, cuisine and key ingredients, so swaps can become ingredient and cuisine facts; `timeZone` places events in ISO weeks and weekdays, ADR 0005). Its signature has no access to rules or members' safety status, and `FactStatement` has no case that maps to a hard rule. v1 statements: `cuisineAffinity`, `dislikesRecipe`, `dislikesIngredient`, `prefersQuickWeekday`, `staple`, `favouriteRecipe`.
- Evidence weight = Σ 0.5^(age/28 days). Proposal when ≥3 events across ≥2 ISO weeks, counting only events within the last 56 days (weight ≥ 0.25); a proposed fact whose qualifying evidence lapses returns to observing (T17 review decision). At most one reflect-back card per week (via `PromptScheduler`). "Don't ask again" suppresses the statement key permanently. "Forget" deletes the fact and records `forgottenAt` so older events are ignored for that key. Editing a fact to another subject (U8) tombstones the old key the same way (suppression kept) and stores the stated fact under a new unique id.
- Facts only feed planner score components (AC-12.6).

## Alternatives considered
1. A unified Fact/Rule store with a hard flag. Rejected: inference could set the flag through a bug. Separate types make that impossible.

## Consequences
- The "What I've learned" screen lists Facts. Hard rules are listed separately under Household & safety.
