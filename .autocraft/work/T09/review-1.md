# T09 review, round 1: CHANGES REQUESTED

- [MAJOR] PlanValidator.swift:42-47: eaters come only from meal.servings, so an active member missing from servings (or servings: []) is never checked — unsafe bypass. Eaters = active members ∪ serving ids, minus explicit notEating (eating serving beats duplicate notEating); order by serving order then household order. Tests: omitted child with peanut rule violates; empty servings violates; soft-deleted missing member ignored; missing member with only a household rule.
- Q1 accepted: a meal nobody eats needs no violation.
Verified: tags from tags ∪ mayContain (declaredTags never read); unverified + hard rule fails; household-scope rules; unknown ids fail closed; conservative merge; contentHash carried.
