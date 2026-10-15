# T11 handoff 2: review-1 fixes

- Branch: local `feat/t11` (worktree `../omp-t11`), on top of the reviewer's merge 3fe2e5a and review dcb76ae. Not pushed.

## Fixes
- [MAJOR] I added a new case, `ExplanationReason.lockedMealNoLongerSafe`.
  - When `regenerate(keepingLocked: true)` replans a locked meal that is no longer safe, that meal's reasons become `[.lockedMealNoLongerSafe, <best score reason>]`. That meal is also unlocked.
  - The same applies if the locked recipe is missing from the library (fail closed).
  - With `keepingLocked: false`, or for meals that were never locked, the reason is never added.
  - Tests in `PlannerEditingTests` (`unsafeLockedReplanned`, `notKeepingLocked`) check that:
    - the reason comes first;
    - the meal has at most 2 reasons;
    - no other meal gets the reason;
    - a locked meal that is still safe never gets it.
  - The Codable round-trip test now includes the new case. Adding a case leaves existing encodings unchanged, so the content-hash goldens are unaffected.
- [MINOR] The performance test now asserts < 2 s, with a comment that the product budget stays 200 ms.
- [MINOR] Added a note on the `prefersQuickWeekday` +1 timeFit bonus to plan.md §5 step 4.

## Follow-up (not in this task)
- The new reason needs UI copy, e.g. "Your locked meal is no longer safe, so we changed it". Copy C-084 lives in docs/design/copy.md and the String Catalog, which belong to ux-designer and T23. I did not edit them.

## Verification
- `bash scripts/check-core.sh --lint-only`: OK.
- No Swift toolchain here, so nothing was compiled or run. CI is the verification of record.
