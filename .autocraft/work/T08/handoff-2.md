# T08 Safety gate: developer handoff 2 (answers review-1)

```
HANDOFF
From: developer            To: pr-reviewer
Status: DONE
Summary: All round-1 items fixed with tests. Not compiled locally; lints green.
Artifacts: local branch feat/t08 (worktree ../omp-t08).
Next: re-review round 2.
```

| Item | Resolution |
|---|---|
| M1 | Fixed. `Household.confirmMemberAnswer(for:at:)`: `stated` if any rule covers the member, else `confirmedNone`; stamps date; rules unchanged. Tests: `addedMemberCoveredByHouseholdRule`, `uncoveredMemberAnswer`, and `ageBandResetKeepsRules` now re-confirms and clears. |
| M2 | Fixed. `SafetyClearance.isValid(for:now:timeZone:)` = `matches` and the gate passes again at `now`. Tests: `clearanceExpires` (unchanged household valid on day 180, refused on day 181), `clearanceInvalidAfterEdit`. `matches` doc says it ignores time. |
| m1 | Fixed. "No, nobody" throws only if a rule covers an active member (household scope or active member scope). Tests: `noNobodyIgnoresDeletedMembersRules`, `noNobodyWithHouseholdRule`. |
| m2 | Fixed. New `SafetyTransitionError.emptyRule(RuleID)` for rules with empty `excludedTags`, in both `addRule` and `confirmSafetyAnswers`. Test: `emptyRuleRefused` (household unchanged). |
| m3 | Fixed. `reconfirmationAcrossDST` (Europe/London, confirmed 2026-07-01 00:30 BST): late local day 180 cleared even though more than 181 x 24 h elapsed; 00:10 on local day 181 due. |
| m4 | Fixed. A confirmation more than 1 day in the future counts as due (fails closed); tomorrow is tolerated for clock skew. Test: `futureConfirmationIsDue`. |
| q1 | Adopted. `removeMember` throws `.lastMember(id)` when only one active member is left. Test: `lastMemberCannotBeRemoved`. |
| n1 | Fixed. `reconfirmSafety` dedupes ids in first-mention order; test passes `["a", "a"]`. |
| n2 | Fixed. `addRule` doc states that every member whose status it sets, including already-`stated` members covered by a household rule, gets `safetyConfirmedAt` re-stamped. |
| n3 | Done. Clearance `rules` excludes member-scope rules of deleted members; `matches` uses the same filter. Test: `clearanceDropsDeletedMembersRules`. |

Also hoisted the remaining mutating call out of an `#expect` expression (`stillCorrectForSomeMembers`). `#expect(throws:)` closures still contain mutating calls; Linux CI accepted these on 0d3f10e.
