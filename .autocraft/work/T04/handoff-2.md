# T04 developer handoff 2 (answers to review round 1)

```
HANDOFF
From: developer            To: pr-reviewer
Status: DONE
Summary: All round-1 items fixed (1 MAJOR, 2 MINOR, 2 NIT). The QUESTION is left for T05 as the
  lead asked. Lints pass locally; Swift build/test is CI only (no toolchain).
Artifacts: feat/t04 (worktree ../omp-t04), head commit in the lead's report.
Next: re-review round 2 in a fresh context.
```

| # | Item | Answer |
|---|---|---|
| 1 | [MAJOR] exact exclusions, "nut", every keyword resolves | Fixed. `BundledSeedTests.exactExclusions` pins the exact `excludedTags` for all 14 chips from a table (`expectedExclusions`), plus a count check. `nutsKeyword` now also asserts "nut" -> peanuts + tree-nuts. `everyKeywordResolves` asserts every catalog keyword selects at least one restriction, and as many as it lists. |
| 2 | [MINOR] reuse T07 `ConversionProfile.canConvert`; lead decision on unquantified defaults | Fixed. `SeedValidator.isConvertible`: an unquantified line is always fine. A quantified line for an ingredient with an unquantified default unit is rejected (`unconvertibleUnit`). Otherwise `ConversionProfile(gramsPerMl:gramsPerPiece:).canConvert(from:to:)` decides. New test `quantifiedLineForUnquantifiedDefault` (hing in grams). The bundled seed still validates: hing (pinch) and curry leaves (toTaste) are only used unquantified. |
| 3 | [MINOR] restriction defect tests | Added `restrictionWithoutTags` (`[]`), `restrictionMissingTagsField` (field absent) and `restrictionUnknownTag` (unknown tag reported; no spurious missing-field issue). |
| 4 | [NIT] AC-4.3 wording | The sheet now says "...is excluded from any meal where someone eating has a hard rule (AC-4.3)." The golden test is updated. |
| 5 | [NIT] `derivedTags` invariant | Documented as a precondition. An unresolved line now fails closed: `assertionFailure` in debug, and in release the result contains every `FoodTag`. So a foreign recipe can never look tag-free. Unreachable for library recipes because the validator rejects dangling lines. |
| 6 | [QUESTION] Hindi keywords, coconut vs tree nut | Deferred to T05 content and the owner's G1 sign-off, per the lead. |
