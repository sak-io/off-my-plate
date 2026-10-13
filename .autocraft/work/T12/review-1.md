# T12 review, round 1: APPROVED (static; hold merge until Linux CI runs the suite)

Not vacuous; no skip mechanisms; gate refusal for all 4 entry points × 5 conditions; 5 lint rules with planted fixtures (test-lints 49/49); separate Safety suite CI step (min 8) and seed-review job. Flagged exception accepted (regenerate clears blockedBySafety only on replanned hard-filtered meals).
Tracked MINORs: public `replacingRecipe` (WeekPlanner+Editing.swift:24) clears blockedBySafety without a clearance — services must validate; PLANNER_HELPERS allow-list keyed by file+name only. NIT: suite runs twice in CI.
