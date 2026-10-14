# T27 review round 2 (delta, commit 8818e32)
1. StoreCompaction.purge: OK. Reads busy column via prepare/step, retries 5x, throws SQLITE_BUSY; statement finalised (inner defer) before close (outer defer) on all paths. Test asserts -wal size 0. Compiles plausibly under Swift 6.2 (Foundation imported, Int32 codes).
   [MINOR] No test for the busy/persistent-busy path (hold a second write connection). [NIT] VACUUM busy is not retried inside purge; the backend's second eraseStore call covers it.
2. deleteAllData: OK. Backend retries erase once then throws StorePurgeError; view model restarts onboarding with purgeIncomplete true, logs, no crash; store/container is not closed (eraseAllData reuses it). Tests cover throwing and successful erase.
   [MINOR] storePurgeIncomplete is not shown to the user (already tracked for T26).
3. cleanName: OK. Strips control/format/line/paragraph separators, trim, prefix(40) by Character, trim. Tests meaningful.
   [MINOR] Stripping all .format drops ZWJ/ZWNJ: breaks ZWJ emoji sequences and Persian/Indic names; .unassigned drops newer emoji on older OS. Consider allowing U+200C/U+200D. [MINOR] No grapheme-cluster cut test.
   addPerson: non-fatal name failure is acceptable (person exists, logged, safety question follows).
4. No safety-path regressions found. HouseholdTabPlaceholder removal has no remaining references. review-1.md was not found at the given paths (reviewed the commit only).
VERDICT: APPROVED
