# T08 Safety gate and safety status: developer handoff 1

```
HANDOFF
From: developer            To: pr-reviewer
Status: DONE
Summary: SafetyGate.evaluate -> Result<SafetyClearance, GateRefusal>, the SafetyClearance
  token (fileprivate init, same file as the gate, not Codable, immutable snapshot), U4
  approval check, TR-3 fail-closed, and all plan 4.1 status transitions as Household
  mutations. NOT compiled locally (no Swift toolchain); lints green.
Artifacts: local branch feat/t08 (worktree ../omp-t08); files below.
Open items: CI is the first compile. Deviations D1-D4 need reviewer agreement.
Next: fresh-context review; lead merges feat/t08 and reads CI.
```

## Files
- `Packages/Core/Sources/OMPDomain/Safety/SafetyGate.swift`: `SafetyClearance`, `SafetyGate`.
- `Packages/Core/Sources/OMPDomain/Safety/SafetyStatusTransitions.swift`:
  `SafetyTransitionError`, `extension Household` transitions, `AgeBand.safetyGroup(of:)` (internal).
- `Packages/Core/Tests/OMPDomainTests/SafetyGateTests.swift`: 3 suites.

## API (for T10/T11/T12 and services)
- `SafetyGate.evaluate(_ household: Household, now: Date, timeZone: TimeZone) -> Result<SafetyClearance, GateRefusal>`
- `SafetyGate.evaluate(_ household: Household, clock: some DomainClock) -> Result<SafetyClearance, GateRefusal>`
- `SafetyGate.approvalRefusal(for: Household) -> GateRefusal?` (U4: unanswered blocks approval; overdue does not)
- `SafetyGate.membersNeedingAnswer(in:)`, `membersDueForReconfirmation(in:today:timeZone:)`, `reconfirmationPeriodDays = 180`
- `SafetyClearance`: `householdID`, `members` (active only), `rules` (hard), `settings`, `issuedAt`,
  `rules(covering:)`, `matches(_ household:) -> Bool`.
- Household: `confirmNobodyAvoidsAnything(at:)` (AC-2.2), `confirmSafetyAnswers(rules:at:)` (AC-2.3/U1/G3),
  `confirmNothingToAvoid(for:at:)`, `addRule(_:at:)`, `removeRule(_:confirmedAt:)`,
  `addMember(role:ageBand:at:id:)` (AC-3.2), `removeMember(_:at:)` (U3), `setAgeBand(_:for:at:) -> Bool` (AC-3.4),
  `reconfirmSafety(for:at:) -> [MemberID]` ("Still correct?", G3). All throwing ones leave the household unchanged on error.

## Semantics
- Unanswered = non-deleted member `unasked`, **or** `confirmedNone`/`stated` with nil
  `safetyConfirmedAt` (TR-3, fail closed as unanswered, which also blocks approval). Unanswered
  takes precedence over overdue. Ids in stored member order. Deleted members never block.
- 180 days counted in whole calendar days in the given time zone: day 180 cleared, 181 due.
- Age-band groups: {infant, toddler, child} vs {teen, adult, senior}; to/from `nil` also resets.
  Reset sets `unasked` and clears `safetyConfirmedAt`; rules kept.

## Deviations / decisions
- D1 ADR 0007 "household fingerprint": implemented as structural `matches(_:)` against the
  snapshot (no SHA256 in Core yet). T10 can add a hash later without changing the token.
- D2 `evaluate` takes `now` + explicit `timeZone` (or a `DomainClock`) instead of `now` only,
  because the 180-day rule counts calendar days (ADR 0005, no implicit time zone).
- D3 `addRule` with household scope does not turn `unasked` members `stated` (nobody answered
  for them); a member-scope rule does (explicit answer). Fail-closed choice.
- D4 `confirmNobodyAvoidsAnything` throws `.householdHasRules` instead of silently deleting rules.

## Tests (map to brief)
Every transition (none, rules per member, Not-sure-who household, per-member none, add rule,
remove rule last/not last, add member, remove member, age-band 9-case table x 2 statuses,
Still correct? all/some); refusal lists right members; 180 vs 181 (+ late on day 180, + Kolkata TZ);
snapshot immutable after household edits; deleted member (unasked and overdue) doesn't block;
TR-3 both statuses; U4 approval.

## Verification
`bash scripts/check-core.sh --lint-only`: OK. Swift build/test: CI only.
