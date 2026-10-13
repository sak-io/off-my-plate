# T14 developer handoff 1

```
HANDOFF
From: developer            To: pr-reviewer
Status: DONE
Summary: Pantry and shopping arithmetic in OMPDomain (Pantry/, Shopping/) with tests.
  Not compiled locally (no Swift toolchain); `scripts/check-core.sh --lint-only` OK.
Artifacts: local branch feat/t14, commit d2cda5e (plus this handoff).
Next: lead pushes; CI (Linux + macOS) must be green; review.
```

## What (by AC)
- `Shopping/IngredientRequirements.swift`: `shoppingMeals` = `plan.usableApprovedMeals` minus cooked, empty and
  past (date < today) meals; per line qty x sum(eating portions) / recipe.servings (AC-6.4); `QuantityTotal` per
  ingredient (AC-10.1). Non-quantified lines skipped. `ShoppingUnits.normalised`: stable display base unit
  (ingredient default unit's dimension, else g/ml/piece), >= 1000 g -> kg, >= 1000 ml -> l.
- `Shopping/ShoppingDerivation.swift`: `derive(plan:recipes:ingredients:pantry:now:timeZone:)`. Pantry counts only
  if resolved, not expired (expiring today still counts), positive quantified (AC-9.2). Confident cover subtracted;
  what low-confidence cover would take becomes a `.checkYouHave` line, the rest `.toBuy` (AC-10.4). Non-convertible
  parts stay separate lines. Key format: `plan:<ingredientId>:<dimension>:<group>`.
- `Shopping/ShoppingListMerge.swift`: `merge` (AC-10.2, AC-10.5) and `boughtEverything` (AC-10.6).
- `Pantry/PantryConfidence.swift`: calendar-day age in the given time zone; confident while age <= 7 (fridge) /
  60 (shelf, freezer); future confirmations are age 0 (AC-9.7).
- `Pantry/MarkCooked.swift`: `proposedAmounts` (throws `MarkCookedError` unless effectively approved, not blocked,
  not empty, not cooked, recipe matches; AC-5.3, AC-9.6) and `deduct` (earliest expiry first, no-expiry last, ties
  by id; clamp at 0; free text never touched; returns `PantryDeduction`s for the CookLog).

## Tests
`ShoppingDerivationTests`, `ShoppingListMergeTests`, `PantryArithmeticTests` (+ `ShoppingFixture`): draft /
edited / superseded plan -> empty; worked examples (80 g dal, 12 ml ghee, 0.8 onion); separate non-convertible
lines; kg display; order independence; confident vs low-confidence vs mixed; decay boundaries 7/8 and 60/61 incl.
time zone; merge keep/clear check-off; Bought everything; deduction order, clamp, conversions, refusals.

## Questions / deviations (recommended defaults implemented)
- Q1 Optional recipe lines (garnish) are included in requirements and Mark cooked. Alternative: exclude.
- Q2 Bought everything: checked "Check you have" lines are removed without adding stock (the user confirmed they
  have it). Arguably they should re-confirm the matching pantry items (`lastConfirmedAt = now`); left to T19.
- Q3 Confidence uses calendar days (day 7 confident, day 8 low), not 24-hour periods.
- Q4 Mark cooked deducts from expired items too (spec: earliest expiry first).
- Bought items with no amount become 1 of the ingredient's default unit (1 piece for free text); fridge items get
  `expiresOn = today + fridgeShelfLifeDays` (capped at 3650 days).
- No pack-size rounding or staples (tech spec section 10) - not in the T14 ACs.
