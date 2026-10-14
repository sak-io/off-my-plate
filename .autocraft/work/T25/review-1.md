# T25 review 1 (light, tier N)
Scope: git diff claude/build-v1...feat/t25. No toolchain; compile/UI results rely on CI (macOS CI currently unavailable: do not merge until green).

## Findings
- [PRAISE] All writes go through ShoppingBackend -> ShoppingService (addManual, setChecked, remove, boughtEverything); the view model never touches repositories. Aisle order, Check-you-have-first, share text and "Check you have" semantics (checked line confirms the pantry via the service, does not add stock) match AC-10.1..10.7 and the service tests.
- [MINOR] "Need it" is highlighted (checkmark + selected trait) by default on every unchecked Check-you-have row, before the user chose anything. Misleading for sighted and VoiceOver users. Show a selection only after a tap, or show no mark on "Need it".
- [MINOR] Deviation "Need it only unchecks": acceptable for AC-10.4 (the item stays in its separate group; the service has no "move to buy" API and the group is derived). But on an unchecked row "Need it" is a no-op. Track: decide in a later task whether Need it should promote the line to the aisle section.
- [MINOR] Deviation "Clear checked unchecks (nothing deleted)": acceptable, no AC specifies delete; copy C-149 is ambiguous. Tracked as a copy question for the owner. Also it issues N sequential setChecked calls (N service transactions); fine at list sizes, note for later.
- [MINOR] Test gap vs the card's Tests line: "Check you have" and "Bought everything updates the pantry" have no UI test. Reasons given (no low-confidence seed; pantry asserted in ShoppingServiceTests) are acceptable; the Check-you-have view-model test uses a fake with the group preset, so it proves ordering only. Track a UI seed with a stale fridge item (and a Pantry-tab assertion after Bought everything) for T28.
- [MINOR] haveItNeedIt VM test is close to tautological (fake setChecked just stores the flag). Fine as a routing test, do not count it as service coverage.
- [MINOR] No xcstrings entries: String(localized:defaultValue:) works with defaults, so no compile/runtime risk. Keys like "C-144.range", "shopping.*" are not copy-deck ids. Track for the localisation task (T28).
- [MINOR] Share header (C-148) comes from Core in English with ISO dates ("2026-10-12 to 2026-10-18") rather than the screen's "Mon 12 - Sun 18 Oct" style; acceptable for AC-10.7, copy.md only gives "{range}".
- [NIT] Wireframe shows "(approved)" after the range; rangeText omits it. Dialog says "Add 1 checked items" for n=1 (copy deck wording, but needs a plural rule later). isBusy disables the add field during add, which can drop keyboard focus.
- [NIT] hasDraft in ShoppingPlanInfo is computed but unused by the view (C-140 shows with or without a draft). Dead field.

## Copy / design
C-140..C-146, C-147, C-095 strings match docs/design/copy.md. Banner, nothing-to-buy, no-plan card, confirmation dialog, menu items present per S-25. ContentUnavailableView correctly avoided (LESSONS).

## Compile / concurrency
Checked names against package source: PlanService.currentSeriesID/activeApprovedPlan/workingPlan/pendingDiff, MealPlan.endDate, LocalDate.adding(days:)/isoString, InlineCard (with and without actions), AdaptiveStack, OMPSymbol.draft/plan/warning, OMPFont.reason/mealName, OMPMetrics.coverMaxWidth, planBarBackground, fixtureNow/utc test globals all exist. LiveShoppingBackend holds Sendable services, so implicit Sendable is fine. CompositionRoot uses LiveShoppingBackend(context:) which matches its init. No likely strict-concurrency failure found.

VERDICT: APPROVED (no BLOCKER/MAJOR; MINOR/NIT to .autocraft/work/tracked.md). Merge only after CI is green on both platforms.
