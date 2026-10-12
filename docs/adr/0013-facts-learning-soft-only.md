# ADR 0013: Facts and learning are soft-only by construction

- **Status:** Accepted (owner: tech §5.2, §8.5; spec US-12, G10; mechanism by architect)
- **Date:** 2026-10-12

## Context
The app may learn preferences but must never create or change hard rules or safety status (AC-12.4).

## Decision
- Hard restrictions are a separate type, `Rule(kind: .hard)`. They can only be created by `SafetyService.confirmSafetyAnswer`, from the safety screen or Settings -> Household & safety.
- `FactLearner.update(facts:events:now:) -> [Fact]` is pure. Its signature has no access to rules or members' safety status, and `FactStatement` has no case that maps to a hard rule. v1 statements: `cuisineAffinity`, `dislikesRecipe`, `dislikesIngredient`, `prefersQuickWeekday`, `staple`, `favouriteRecipe`.
- Evidence weight = Σ 0.5^(age/28 days). Proposal when ≥3 events across ≥2 ISO weeks. At most one reflect-back card per week (via `PromptScheduler`). "Don't ask again" suppresses the statement key permanently. "Forget" deletes the fact and records `forgottenAt` so older events are ignored for that key.
- Facts only feed planner score components (AC-12.6).

## Alternatives considered
1. A unified Fact/Rule store with a hard flag. Rejected: inference could set the flag through a bug. Separate types make that impossible.

## Consequences
- The "What I've learned" screen lists Facts. Hard rules are listed separately under Household & safety.
