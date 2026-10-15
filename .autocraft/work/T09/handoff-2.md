# T09 handoff 2 (response to review-1)

- [MAJOR] eaters only from servings: **Fixed.** `PlanValidator.eaterIDs(of:household:)` (private) =
  serving member ids ∪ `household.activeMembers`, minus members whose only servings are `notEating`
  (an eating serving beats a duplicate notEating one). Order: serving order, then remaining active
  members in household order. Soft-deleted members not in servings are ignored; serving members
  not in the household (or soft-deleted) are still checked. Doc comments updated.
- New tests (PlanValidatorTests.swift): omitted child with peanut rule violates; empty servings
  checks everyone in household order; soft-deleted missing member ignored; missing member with only
  a household rule violates; eating beats duplicate notEating; eater order servings-then-household.
- Q1 (meal nobody eats): accepted, unchanged (only reachable now when every active member is
  explicitly notEating).
- Handoff-1 question 4 is resolved by this change.
- Verification: `scripts/check-core.sh --lint-only` OK. Not compiled locally (no toolchain); CI is the record.
