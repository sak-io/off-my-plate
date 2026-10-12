# T08 review, round 1: CHANGES REQUESTED

No path issues a clearance while a member is unanswered/overdue. Lint green on a fresh clone. D1–D4 accepted (D3 conditional on M1; D4 with m1).

- [MAJOR] M1: unasked member already covered by existing rules (added after a household-scope rule; age-band reset keeping rules) can only be unblocked by inventing/removing rules. Add `confirmMemberAnswer(for:at:)` → stated if covered else confirmedNone, stamps date; tests for both cases.
- [MAJOR] M2: `matches(_:)` ignores time; a clearance from day 170 still matches on day 400 → bypasses re-confirmation. Add `isValid(for:now:timeZone:)` (matches + same local day, or re-run gate) and a test.
- [MINOR] m1: deleted members' member-scope rules block "No, nobody" forever; guard only on rules covering active members or household scope; test.
- [MINOR] m2: reject rules with empty excludedTags; test.
- [MINOR] m3: DST-crossing 180-day test (Europe/London or America/New_York).
- [MINOR] m4: future-dated confirmation (> today+1) counts as due; test.
- [QUESTION] q1: refuse removing the last active member (`.lastMember`). Lead decision: yes, adopt.
- [NIT] n1 dedupe reconfirm ids; n2 doc that household-scope addRule re-stamps; n3 optionally filter deleted members' rules from clearance.
