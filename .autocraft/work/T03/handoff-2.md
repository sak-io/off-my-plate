# T03 Domain contracts: developer handoff 2 (answers to review-1)

```
HANDOFF
From: developer            To: pr-reviewer
Status: DONE
Summary: Fixed the MAJOR (ValidationReport is Encodable only), the EntityID empty-id and
  single-household MINORs, and the EntityID doc NIT. Added golden-JSON decode tests. The
  remaining notes are listed below as tracked items for the team lead to copy into
  .autocraft/work/tracked.md.
Artifacts: feat/t03 at 95eba08 (fixes) plus this file.
Open items: CI must compile 95eba08 (no local toolchain).
Next: round-2 review.
```

## Responses
- [MAJOR] ValidationReport is Decodable, so it could be forged: **Fixed in 95eba08.** It now
  conforms to `Encodable, Sendable, Hashable`, so there is no `init(from:)`. The exception and
  the reason for it are documented on the type. The test now encodes the report and round-trips
  only `[Violation]`. **New deviation D8:** ValidationReport is not Decodable, the one exception
  to "all §3.1 types are Codable"; a stored report is never trusted.
- [MINOR] `package` init lets any Core target build a report: **Tracked (T09/T12), see TR-1.**
- [MINOR] Stored JSON shapes not pinned: **Fixed in 95eba08.** New `GoldenJSONTests` suite in
  `CodableRoundTripTests.swift` decodes hand-written JSON for:
  - PlannedMeal with reasons, servings and absent optionals;
  - a member-scoped Rule;
  - both PantryItemRef cases;
  - LearningEventKind with the optional reason present and absent;
  - FactKey for a member and for the household.

  The goldens are decode-only, so the unstable `Set` encoding order never matters. The final
  persisted format is still owned by T20's DTOs (TR-4).
- [MINOR] An empty EntityID encodes but can't decode: **Fixed in 95eba08.** `encode(to:)`
  throws `EncodingError.invalidValue` for an empty id. New test
  `EntityIDTests.emptyDoesNotEncode`. I did not add a precondition in the inits: a crash on a
  bad seed id seemed worse than a thrown error at the storage boundary.
- [MINOR] Single-household rule not enforced: **Fixed in 95eba08.** The protocol requirement
  is now `replace(with:)`, documented as "at most one household; replaces whatever was
  stored, even with a different id". The in-memory implementation sets `items = [household]`.
  New test `singleHousehold` replaces h1 with h2 and checks that only h2 remains.
- [MINOR] No atomic multi-entity save: **Tracked (T18/T20), see TR-2.**
- [MINOR] Confirmed status with a nil `safetyConfirmedAt`: **Tracked (T08), see TR-3.**
- [NIT] EntityID ordering doc: **Fixed in 95eba08.** It now says Swift `String` ordering
  (Unicode canonical equivalence, locale-independent), not "scalar order".
- [NIT] `LocalDate.safelyAdding` for user input: **Tracked, see TR-5.**

## Tracked items (team lead: please append to `.autocraft/work/tracked.md`)
| ID | Task | Item |
|---|---|---|
| TR-1 | T09/T12 | `lint-safety.sh`: `ValidationReport(` may appear only in `Sources/OMPSafetyCheck/` and `Tests/` (the `package` init is visible to every Core target). |
| TR-2 | T18/T20 | Approve and similar flows write several entities (plan statuses, approval, shopping). Add an atomic multi-entity save/transaction to the repositories before `approve` ships. |
| TR-3 | T08 | `SafetyGate` must fail closed when a member is `confirmedNone`/`stated` but `safetyConfirmedAt == nil`: treat it as unasked or as re-confirmation due, with a test. |
| TR-4 | T20 | The persisted format is owned by the OMPData DTOs. Keep the T03 golden JSON tests in step with the DTOs, or add DTO goldens. |
| TR-5 | T16/T24 | Add a failable `LocalDate.safelyAdding(days:)` (no precondition) before any user-entered offset reaches date arithmetic. |

## Evidence
`scripts/check-core.sh --lint-only` is green (self-tests 9/10/36, both lints OK). The code is
not compiled locally. The signatures I relied on are `EncodingError.invalidValue(_:_:)` and
`EncodingError.Context(codingPath:debugDescription:)`, and `#expect(throws: EncodingError.self)`.
