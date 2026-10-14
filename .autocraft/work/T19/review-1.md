# T19 review-1 (pr-reviewer, Sonnet) - feat/t19 vs claude/build-v1

VERDICT: CHANGES REQUESTED

Reviewed by reading (no Swift toolchain). CI (batch-2, d98f4c2) is assumed to cover compile/test results.

## Findings

[MAJOR] DirectoryInboxStorage (InboxStorage.swift) has no test at all. It is the production implementation of quarantine -> `failed/`
(card test "a corrupt file goes to failed/"), of the 256 KiB size guard, of path-escape rejection, and of the "delete all" inbox wipe
(AC-16.2). Every service test uses InMemoryInboxStorage, so none of the real file moves is verified. It is Core code and runs on Linux CI.
Add a temp-directory test: quarantine moves the file into `failed/` (and overwrites an older same-name file), oversize file ->
fileTooLarge, `../x.json` / non-inbox names rejected, `deleteAll` removes root including `failed/`, `fileNames` on a missing root is [].
Optionally run one drain through ImportService + DirectoryInboxStorage with a garbage file.

[MINOR] ImportService quarantines on ANY read/decode error. A transient read failure (permission, notFound race, I/O error) moves a
perfectly good file to `failed/`. Only InboxImportError (decode/validation/too large) should quarantine; other storage errors should go to
`summary.stuck` and be retried next drain.

[MINOR] PantryService.markCooked comment says "Last, so an interrupted call can be repeated". The pantry deductions and CookLog are
saved before the plan's cooked ref, so repeating after an interruption deducts a second time (and writes a second log). The ordering
avoids "cooked with no log" but not double deduction. Fix the comment, or write the log + cooked ref first and the deduction last. Track it
if deferred.

[MINOR] No test that Mark cooked refuses a `blockedBySafety` meal on an otherwise approved plan (code does: `.markCooked(.blockedBySafety)`).
Safety-adjacent branch; add one test (rule change after approval -> recheck -> markCooked refused).

[MINOR] confirmVoice `.add` stores `.ingredient(id)` for ids not in the library and creates duplicate rows when the ingredient is already
in the pantry. The commands come from the UI card after user edits, so validate ids (`unknownIngredient`) like `resolve`/`pantryRef` do.
Duplicates are acceptable if intended; say so.

[MINOR] Pruning removes learning events but not the facts they produced. Inferred, unconfirmed facts then decay to `observing` on the next
refresh (confirmed/stated facts are untouched, per FactLearner). That is probably intended; a one-line doc note on `prune()` would stop
a later "my learned fact vanished" report.

[QUESTION] DirectoryInboxStorage.deleteAll removes the whole Inbox folder. Does the Share Extension recreate it when writing
(createDirectory withIntermediateDirectories)? If not, imports silently fail after "Delete all data". Confirm in T26.

[NIT] `PantryService.markCooked` accepts caller-edited `amounts` unchecked (ingredient not in recipe, huge values). Deduct clamps at zero
so it is safe; fine to leave.

[PRAISE] drainInbox idempotency design (processed-id store before delete, leftover file removed without merge, id-vs-filename check,
third-drain case tested). Imports only call logStaples + shopping/pantry repos; ImportService has no household/safety handle, and the
test proves household unchanged. Mark cooked gated on isEffectivelyApproved first, then blockedBySafety. Prune boundary (exactly-cutoff kept,
-1s removed, facts kept) and delete-all (asserts non-empty first, covers all 8 repos + processed + counters + inbox/failed + repeat) are
well tested. No SafetyGate/validator/clearance bypass; no new unblock calls (lint-safety unaffected).

## Compile-risk scan (Swift 6.2)
No problems found by reading: `serialized` takes a non-escaping closure so implicit self is fine; actors satisfy async protocol
requirements with sync methods; `mappingDomainErrors { () throws -> ... }` has explicit type; ServicesBEnv/ServiceContext usage matches
existing T18 patterns. Residual CI-only risks: the importsAreStapleEvidenceOnly expectation `kinds.count == 3` assumes the string
"peanut allergy - nuts are fine now" does NOT confidently resolve to an ingredient (if it does, count is 4); the cutoff test hardcodes
2025-10-12T00:00Z (depends on fixture time zone).

## Owner-decision assumptions
1. keyIngredients = first two non-optional lines: SAFE default. Soft preferences only (FactStatement cannot express a restriction),
   never read by safety. Worst case is weak "likes X" proposals that the user can dismiss/forget. Keep tracked.
2. Imported item whose ingredient is on the plan becomes its own "from Notes" row: SAFE. Plan lines stay a pure function of plan+pantry
   (no edit/loss risk); the cost is a possible double buy, which the user sees and can delete. Keep tracked as UX.

## Disposition
Safety-critical? No (no gate/validator/planner/approval touched) but one MAJOR test gap. After the DirectoryInboxStorage tests are
added, a delta check suffices; MINORs may be tracked in tracked.md.
