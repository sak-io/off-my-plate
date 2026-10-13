# T11 review, round 1: CHANGES REQUESTED

Safety PASS (clearance checked at every entry point; only hard-filtered candidates; fail-closed eaters; only active stated/confirmed Facts score; locked meals kept only if still safe; agreement tests cover editing).
- [MAJOR] WeekPlanner+Editing.swift:201-206: a locked meal replanned because it became unsafe gives no signal to the UI. Add e.g. ExplanationReason.lockedMealNoLongerSafe first in reasons (or return replanned ids) + test.
- [MINOR] PlannerScoringTests.swift:306-329: 200 ms wall-clock assertion → ≥2 s bound or no assert.
- [MINOR] Document prefersQuickWeekday +100 in plan.md §5.
Decisions 1–4 accepted with those conditions.
