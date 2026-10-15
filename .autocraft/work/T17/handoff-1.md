# T17 handoff 1: Facts learner and prompt scheduler

- **From:** developer -> **To:** pr-reviewer
- **Branch:** `feat/t17` (local worktree, based on `claude/build-v1`)
- **Task:** `docs/architecture/tasks.md` T17; ADR 0013; AC-7.1, 7.3, 7.4, 12.1-12.5; G10; UX U8, U11.

## What
- `Learning/ISOWeek.swift`: ISO 8601 week from `LocalDate` by pure integer arithmetic (Thursday rule, no `Calendar`); `init(containing:in:)` takes the time zone explicitly.
- `Learning/FactLearner.swift`: pure `FactLearner.update(facts:events:recipes:now:timeZone:) -> [Fact]`.
  - Signals -> soft statements (G10): swap -> `dislikesRecipe(from)`, `dislikesIngredient` for key ingredients not in the replacement, `cuisineAffinity(to)` if the cuisine changed; re-roll "too long" on Mon-Fri -> `prefersQuickWeekday`, other re-rolls and skips -> `dislikesRecipe`; cooked -> `favouriteRecipe` + `cuisineAffinity`; import -> `staple`.
  - Weight `0.5^(age/28d)` (future events = age 0); confidence = min(1, weight/5).
  - Proposal: >= 3 distinct event ids across >= 2 ISO weeks.
  - Answers come in as `.reflectBackAnswered` events: Yes -> `active`/`confirmed` (still soft); Not really -> `dismissed`, and only evidence after the answer counts towards a re-proposal; Don't ask again -> `suppressed`, permanently (survives Forget).
  - `forget(_:now:)` keeps a `.forgotten` tombstone with `forgottenAt`; older events and answers are ignored.
  - `restate(_:subject:statement:now:)` (U8) -> `stated`/`active`.
  - Stated, confirmed and default facts are never changed by inference.
  - New facts are household-level with a key-derived `stableID(for:)` (deterministic).
- `Prompts/PromptScheduler.swift`: `PromptScheduler.next(candidates:states:now:timeZone:) -> PromptCandidate?`.
  - Ordering: safety first (exempt from caps and cooldowns); then a card still open this ISO week stays visible; then cards that were answered are never shown again (lunchbox Yes/No, U11); "Not now" starts a 14-day cooldown; at most 3 distinct non-safety cards per ISO week; at most 1 reflect-back card per week; lunchbox before reflect-back, then ties by id.
  - Helpers: `markShown`, `record(LunchboxPromptAnswer)`, `record(ReflectBackAnswer)`, `PromptCandidate.reflectBacks(from:)`.

## Deviations / decisions for review
1. **[Architecture deviation, small]** ADR 0013 names `update(facts:events:now:)`. I added `recipes: [RecipeID: RecipeTraits]` (cuisine + key ingredients only, no tags or rules) because swaps cannot become ingredient or cuisine facts without it. I also added `timeZone:` for the ISO-week and weekday logic (ADR 0005). The signature still cannot reach a `Rule`, `Household`, `Member` or safety status. T19 builds `RecipeTraits` from `Recipe` (T04).
2. Prompt kinds are identified by id prefix (`safety:`, `reflect:`), plus `lunchbox`, because `PromptState` (T03) stores only ids. Use `PromptCandidate.safety(_:)`, `.reflectBack(_:)` and `.lunchbox` to build them.
3. Reflect-back re-proposal after "Not really": the card's `answeredAt` blocks it only within the same ISO week. A candidate exists only while its fact is `proposed`.
4. Cooldown is 14 x 86,400 s from `dismissedAt`, not calendar days.
5. Confidence scale (`fullConfidenceWeight = 5`) is my assumption. The ADR does not set it.

## Tests (Swift Testing, `Tests/OMPDomainTests/`)
- `ISOWeekTests`: known year-boundary weeks (2020-W53, 2026-W53, 2025-W01, ...); a 1999-2031 day sweep (weeks start Monday and advance by one); the time zone decides the week of an instant.
- `FactLearnerTests`: 2 vs 3 events; 1 vs 2 ISO weeks (Sun 23:00 / Mon 01:00); duplicate ids; decay values (tolerance 1e-9) and confidence decay; determinism and idempotence; Yes / Not really (fresh-evidence boundary) / Don't ask again (permanent, survives Forget); Forget ignores older evidence and old answers; stated facts untouched; restate; signal mapping; weekend "too long"; compile-level signature pin; exhaustive `FactStatement` switch; 100 dairy swaps -> only soft proposed facts, and confirming keeps them soft.
- `PromptSchedulerTests`: empty; safety first and exempt; ordering; 14-day boundary; lunchbox Yes/No are final; weekly cap and Monday reset; safety shows not counted; 1 reflect-back per week; open card stays; reflect-back re-proposal; candidates from facts.

## Evidence
- `bash scripts/check-core.sh --lint-only`: OK.
- No Swift toolchain here, so build and tests were **not run locally**. CI (Linux swift 6.2 and macOS) is the verification of record once the lead pushes.

## Risks
- Not compiled locally. I checked the signatures by hand.
