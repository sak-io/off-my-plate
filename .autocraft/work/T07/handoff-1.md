# T07 Units and quantity arithmetic: developer handoff 1

```
HANDOFF
From: developer            To: pr-reviewer
Status: DONE
Summary: Quantity + conversions on top of T03's MeasureUnit/MeasureDimension: unit factors
  (g/kg, ml/l/tsp 5/tbsp 15/cup 240, piece/dozen), cross-dimension conversion through mass via
  gramsPerMl/gramsPerPiece, add/subtract/scale clamped at zero, non-quantified units never
  convert, QuantityTotal keeps non-convertible amounts as separate parts. NOT compiled locally
  (no Swift toolchain); lints pass.
Artifacts: local branch feat/t07 (worktree ../omp-t07), commit 2a76f89 (+ this handoff commit).
Open items: 1. CI (Linux swift:6.2 + macOS 6.2.4) is the first compile.
  2. Deviations below need reviewer agreement.
Next: review in a fresh context; the team lead merges feat/t07 and reads the CI result.
```

## What and why
Task T07 (tasks.md), plan section 10 "Units" rules; spec AC-6.4 (recipe qty x portions,
unit-normalised), AC-9.6 (pantry deduction never below zero), AC-10.1 (list = sum - pantry,
unit-normalised, non-convertible lines kept separate).

## Files
- `Packages/Core/Sources/OMPDomain/Units/Conversion.swift`: `MeasureUnit.isQuantified`,
  `.baseUnit`, `.baseUnitsPerUnit`; `ConversionProfile` (gramsPerMl?, gramsPerPiece?,
  `init(ingredient:)`, `.none`, `factor(from:to:)`, `canConvert(from:to:)`). Zero/negative/
  non-finite factors are treated as unknown.
- `Packages/Core/Sources/OMPDomain/Units/Quantity.swift`: `Quantity` (amount, unit;
  `converted(to:using:)`, `inBaseUnit`, `adding/subtracting(_:using:) -> Quantity?`,
  `scaled(by:)`, `isZero`, `isCompatible`); `QuantityTotal` (`add`, `subtract` returning
  the uncovered excess, `scaled(by:)`, `quantifiedParts`, `isZero`).
- `Packages/Core/Tests/OMPDomainTests/QuantityTests.swift`: 4 suites (factor coverage,
  17-row parameterised conversion table with round trip, missing/invalid factors, non-quantified
  units, clamping on create/decode/subtract/scale, non-convertible kept apart, seeded SplitMix64
  property test 1000 cases a + b - b ~= a at 1e-9 relative tolerance, QuantityTotal merge /
  separate / pantry subtraction / scaling).

## Deviations / design choices (please confirm)
- D1 Name: tasks.md says `Unit`; we build on T03's `MeasureUnit` (T03 deviation D2).
- D2 Invariant: `Quantity` clamps negative/NaN/infinite amounts to 0 on init and decode, and
  non-quantified units always carry amount 0 (recipe lines ignore their quantity).
- D3 Arithmetic returns the result in the left operand's unit and nil when not convertible
  (callers keep separate lines). Display normalisation (e.g. 1500 g -> 1.5 kg) is left to the
  shopping task T14; `inBaseUnit` is provided.
- D4 Count <-> volume converts only when both density and piece weight are known (via mass).
- D5 No Package.swift change; Ingredient fields are taken via `ConversionProfile` values.

## Verification
- `bash scripts/check-core.sh --lint-only`: OK.
- Swift build/tests: CI only.
