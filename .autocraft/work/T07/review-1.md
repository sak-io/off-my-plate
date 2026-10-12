# T07 review, round 1: CHANGES REQUESTED

Lint green on a fresh clone; no compile blockers found by reading. D1–D5 accepted (D3 with a doc note).

- [MAJOR] Quantity.swift:46,76-79,126-137: no floating-point tolerance in production; 0.1 kg + 0.2 kg − 300 g leaves 5.55e-17 kg so isZero is false → phantom shopping lines. Snap to 0 when result <= 1e-9 × max(a, b) via one `Quantity.relativeEpsilon`; same for `excess`; tests (0.1+0.2 kg − 300 g; 1 l − 1000/15 tbsp).
- [MINOR] Conversion.swift:192: rename `ConversionProfile.none` (clashes with Optional.none) to `.sameDimensionOnly`.
- [NIT] +inf from arithmetic clamps to 0 (document or saturate); [NIT] compute `amount * fromBase / toBase`.
- [QUESTION] Doc note: QuantityTotal keeps the first-seen unit; caller normalises for display (T14).
