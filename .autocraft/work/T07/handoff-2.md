# T07 Units and quantity arithmetic: developer handoff 2 (response to review-1)

```
HANDOFF
From: developer            To: pr-reviewer
Status: DONE
Summary: All review-1 items addressed in 90a5ded. Lints pass; not compiled locally (CI first compile).
Artifacts: local branch feat/t07, commit 90a5ded (+ this handoff commit).
Open items: none
Next: re-review round 2.
```

- [MAJOR] epsilon: Fixed in 90a5ded. `Quantity.relativeEpsilon = 1e-9`; `subtracting` and the
  `QuantityTotal.subtract` excess use `snappedDifference` (diff <= eps * max(|a|, |b|) -> 0).
  Tests `subtractionSnapsRoundingNoiseToZero` (0.1 + 0.2 kg - 300 g),
  `litreMinusTablespoonsIsZero` (1 l - 1000/15 tbsp, also in a total with zero excess),
  plus `smallRealDifferenceKept` (1 kg - 999 g = 0.001 kg). The property test now asserts
  the bound the snap guarantees: |back - a| <= 2 * eps * max(1, sum).
- [MINOR] rename: Fixed in 90a5ded. `ConversionProfile.sameDimensionOnly` everywhere (defaults, tests).
- [NIT] +inf: Fixed in 90a5ded. Init saturates +inf to `Double.greatestFiniteMagnitude`; NaN and
  negatives (incl. -inf) stay 0; `scaled(by:)` accepts +inf (0 x inf = NaN -> 0). Tests updated.
- [NIT] precision: Fixed in 90a5ded. `ConversionProfile.convert(_:from:to:)` computes
  `amount * fromBase / toBase` (via grams across dimensions); the public `factor(from:to:)`
  is replaced by it (unmerged API, no callers).
- [QUESTION] doc note: Added on `QuantityTotal`: parts keep the first-seen unit; display
  normalisation is the caller's job (T14).

## CI follow-up (CI on 11e2b69)
- Failing test `subtractPantry`: Fixed in 3da00e6. The test was wrong. The documented contract,
  which the code already followed, is that the excess comes back in the subtracted quantity's
  unit. Subtracting 1 kg therefore reports 0.4 kg, not 400 g.
- Warning "#require never equals nil" in `mergesConvertible`: Fixed in 3da00e6. The `#require`
  sat inside `approx(Quantity?, ...)`, so it was inferred as optional. It now binds
  `let first: Quantity`.
