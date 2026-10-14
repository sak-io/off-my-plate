# T23 review-1 (pr-reviewer, Sonnet) — plan approval path

VERDICT: CHANGES REQUESTED

Reviewed statically (no Swift toolchain); CI still has to compile and run tests/audits.

## Verified OK (safety-critical)
- [PRAISE] `UserConfirmation()` is created only in `ApprovalWeekBar.swift` and `ApprovalSheet.swift`, both inside Button actions. `PlanViewModel.approve(confirmation:)` has a draft-only guard. `handleSpokenTranscript` only sets `sheet = .approval` and is gated on `canOpenApproval`. VM test asserts `approveCalls == 0`. Lint allows `Approval*.swift`.
- [PRAISE] All mutations go through `PlanBackend` -> services (gate + validator at call time). No local state flip to approved. Revision edits keep approved plan active (`approvedPlan` vs `plan`). Validator failure (C-071) in sheet disables Approve and regenerates.
- [PRAISE] Mark cooked absent on first draft (`approvedPlan == nil`); on a pending revision it acts on the approved counterpart; excludes empty, cooked, `blockedBySafety`, future-dated. Gate-blocked disables Regenerate/Swap/Approve/Review (bar, sheet, voice). Copy ids and strings match copy.md for C-050..C-081, C-084.

## Findings
- [MAJOR] R1 state is not shown anywhere (task AC "R1 state"). `blockedBySafety` is read only in `cookableMeal`. An approved plan whose meal became unsafe (e.g. peanut rule added) renders like a normal meal; Mark cooked just silently disappears; no C-083 card ("Your safety answers changed. Some meals need replacing. Update plan"), no row/detail marker. Need: row + detail marker (text+icon) for `blockedBySafety`, C-083 card with an Update plan action that creates the draft revision via the service (regenerate/revision), and a test (VM-level at least).
- [MAJOR] Regenerate-keeps-locked test is vacuous. `FakePlanBackend.regenerate` returns the same plan, so `meals[0].locked == true` is trivially true; the fake ignores `keepingLocked`, and `LivePlanBackend.regenerate` passing `keepingLocked: true` is untested. UI test compares only the locked row label and never asserts that an unlocked meal could change, so it also passes if the planner is deterministic and regenerate is a no-op. Fix: fake that replaces unlocked meals and honours locks (assert unlocked changed, locked identical and still locked); in the UI test also record at least one unlocked label changed (or assert the changed-count) so a no-op regenerate fails.
- [MAJOR] Dead end for `reconfirmationDue` (180-day, G3). `isBlocked` is true, so planning is blocked, but the card says "Answer the safety question…" and `Answer now` only calls `app.refresh()`, which never shows a cover for `reconfirmationDue`. The user cannot recover from the Plan tab; a button that does nothing on a safety block is not acceptable. Either implement the C-040 "Still correct?" card (Yes, still correct -> service reconfirm / Make changes -> S-33) or, minimum, route the button to the safety-answer flow and hide it where no path exists. Deferral only if a named task is tracked AND the no-op button is removed.
- [MAJOR] AC-6.2/6.3 (adjust portions, set a member to Not eating) are in T23's AC list but not delivered; portions are read-only. The cause is a Core gap (no servings-edit service), so this is an acceptable deferral only if the team lead records it as an owner-visible deviation in tracked.md with a Core task (servings edit through the services + validator, editing an approved plan creates a revision per AC-5.4) before T23 is called done. Not a code fix in this PR.
- [MINOR] `onMarkCooked` is nil so the visible "Mark cooked" button does nothing (also in UI test: asserts existence only). Acceptable until S-15 (T24) but track it; consider disabling/hint so it is not a silent no-op if shipped.
- [MINOR] "Empty-slot reason visible" has no UI test (only `toggleWhy` state in VM test). Seed cannot make an empty slot; add a VM-level test that asserts the row model (empty -> C-064 text/why id) or track.
- [MINOR] C-081 shown as a permanent visible line rather than an alert on tap. Disabled controls cannot be tapped, so the visible text is the better a11y outcome; update screens.md to match rather than change code. `openSwap` still raises the alert if called programmatically; fine.
- [MINOR] Self-coined ids need numbering in copy.md (ux-designer): C-062b/c, C-070a.*, C-070b.*, C-084.*, C-052.retry, C-063.action, C-071.ok, C-073.*, C-074.replace, C-075.*, C-076.*, C-078.not, C-079.*, plan.slot.*, plan.someone, plan.regenerate. "View list" action on C-065 toast is omitted (T24).
- [MINOR] Safety summary C-061 + Change omitted; ingredient quantities (S-11) not shown (names only); no C-082 new-member card. Defer to tracked.md (C-061 -> with S-33 task; quantities -> T24). iPad split view -> T28.
- [MINOR] Discard is reachable only from the approval sheet, which cannot open while blocked; a pending revision can then be neither discarded nor approved until the gate clears. Acceptable (safe direction), note in tracked.
- [NIT] `swapMealID` is not cleared when the swap sheet is swiped away; `ApprovalSheet` discard button indentation is off.
- [NIT] `approve` relies on the service for the gate; adding `!isBlocked` to the VM guard would give defense in depth.

## Compile-risk scan (none certain)
`GateStatus` exists in both OMPServices and OMPFeatures; module-local wins in OMPFeatures, but the test target imports both (`PlanViewModelTests` uses neither name directly - OK). `blockingName` switch is exhaustive over the 6 OMPFeatures cases; `handle` switch has default; `PlanSheet`/`PlanAlert`/`PlanStatusKind` switches exhaustive. `discard` is `@discardableResult`. `PlanBackend: Sendable` with `PlanningLibrary: Sendable` fine. `PlanApprovalOutcome.approved` was not verified by grep; CI will tell.

## Round
Round 1 of 3 (safety-critical: full review loop continues).
