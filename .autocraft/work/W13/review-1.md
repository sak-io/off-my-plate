# W13 review 1 (f0443d2 vs origin/claude/integration)
CI: web-facade, core-linux, core-wasm all success on f0443d2. Swift not run locally.

1. Mark cooked: cook.mark goes to PantryService.markCooked; golden shows planNotApproved before plan.approve, alreadyCooked after. No new approval path; UserConfirmation( only in ApprovalBridge.swift (+ iOS UI files, unchanged); core/ and scripts untouched.
2. Import: ImportService only; preview ops build views and save nothing (test asserts); 256 KiB text/bytes cap, base64 cap, NUL/invalid UTF-8 -> not_text, BOM stripped; household/rules compared before/after import in test.
3. data.deleteAll: needs confirmed:true (missing -> bad_request, false -> confirmation_required); clockExempt; replaces engine with fresh repos/IDSource/inbox/counters; export test checks all empty, idCounter 0, no household.
4. Bounds: checkAmount/checkName/ingredient/date-year/limits on counts before service calls. state.import: stricter amount checks only add rejections; date-shape now requires digits, and real dates in date fields still go through Codable plus range check, so forgery protections are not weakened. Latest-stored-date now includes pantry/cookLogs/events/facts (stricter clock_behind_state).
5. Forgotten facts: test covers forget -> list, refresh, export/import, refresh again, status stays forgotten.
6. Tests meaningful, none skipped; min-test-count 35->50 and goldens list extension legit. transcript-w13 golden content is plausible and correct (refusal before approval, bound errors, not_text, deleteAll results).

MINOR: none blocking.
VERDICT: APPROVED
