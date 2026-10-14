# T27 review 1 (pr-reviewer, Sonnet) - feat/t27 @ 3ee7595
Scope: tier S for safety/delete-all/HouseholdService.setName; tier N for the rest. No Swift toolchain; CI not seen.

VERDICT: CHANGES REQUESTED

## Safety checks that PASS
- Rules/answers change only via SettingsBackend -> SafetyService (addRules/removeRule/reconfirm); views call them after "Yes, save this" / C-036 alert / "Yes, still correct". Unrecognised words block Continue (AC-2.4). Removing the last rule: Household.removeRule moves .stated -> .confirmedNone (explicit alert first); gate not bypassed.
- Learning is soft: LearningService/FactLearner take FactStatement only; test learningIsSoftOnly asserts rules+members unchanged. Fact sheet has no "never/allergic".
- 180-day card: reconfirm() -> SafetyService.reconfirm; test asserts safetyConfirmedAt == now and gate .clear.
- Delete all: C-161 alert needs "Delete everything"; deleteAllRecords covers ProcessedImport + Counter records; dataWasDeleted -> onboardingActive; shell swaps tabs for onboarding (tab state discarded). Failure path keeps tabs (tested). No UserDefaults use exists to clear.
- Debug-only: UITestSeed incl. learned/stale is inside #if DEBUG. Copy ids C-040*, C-100..103, C-154, C-161 match copy.md.
- Swift 6.2 read-through: no compile problem found. `$model.scope` / `$model.draftText` on @State @Observable is fine (ReferenceWritableKeyPath); Picker tags use Hashable RuleScope/FactSubject/nested Strength; the `(prefer:avoid:)?` tuple and `pair != nil` are fine; State(initialValue:) assigned on every init path; storeURL/location are public; PlanTabView closure is @MainActor in a MainActor View init. Verify FactSubject and RuleScope are Hashable (CI will say).

## Findings
[MAJOR] StoreErase.swift purge: result of `PRAGMA wal_checkpoint(TRUNCATE)` is not checked. SQLite reports a blocked checkpoint in the result row (busy=1), not as an error code from sqlite3_exec, so a busy store silently leaves the WAL (with the old rows) on disk while delete-all reports success. The privacy guarantee of AC-16.2 is then unverified. Fix: run the pragma with a callback (or sqlite3_prepare/step) and throw if busy != 0 (retry once after a short wait); also assert in the test that `-wal` is absent or size 0.

[MAJOR] Delete-all failure after records are already gone: LiveSettingsBackend.deleteAllData deletes records, then eraseStore may throw (SQLITE_BUSY from VACUUM/open). HouseholdViewModel then shows "delete failed" and does NOT call dataWasDeleted, though the household is already empty (app.refresh sets gate .noHousehold but onboardingActive is only set in refresh when it sees .noHousehold - confirm - otherwise the user is in limbo on empty tabs). Fix: split the outcome - once records are deleted always call dataWasDeleted (restart onboarding) and surface/log the purge failure separately, or retry the purge; add a test with a throwing eraseStore after successful record delete.

[MINOR] StoreEraseTests: `contentsOfDirectory` is not filtered; Core Data may create a hidden `.default_SUPPORT` directory and `Data(contentsOf:)` on a directory throws -> test fails/flaky on macOS CI. Filter to regular files (resourceValues isRegularFile). Scanning with SwiftData's connection still open is otherwise acceptable because purge opens a second connection and VACUUM + TRUNCATE rewrite everything; the test only asserts the byte marker, not -wal size (see MAJOR 1).

[MINOR] HouseholdService.setName validation: trims whitespace and cuts at 40 but does not strip interior control/format characters (newlines, bidi overrides, Cf) - LESSONS #6 says use TranscriptSanitiser or equivalent. Also prefix(40) happens after trim and can leave trailing whitespace (trim again). Tests cover trim/clear/long/unknown member but none for control chars, empty-after-sanitise, or removed member. Add them.

[MINOR] "Delete all" does not clear the App Group inbox, and CompositionRoot does not pass `dataService`/`counters` (T19 follow-up row in tracked.md, owner T26). The doc comment on SettingsBackend.deleteAllData promises "the inbox"; reword or leave a tracked row for T26 naming this (Store-level records, including ProcessedImport and Counter, ARE emptied via eraseStore).

[MINOR] addPerson = addMember then setName: not atomic; if setName fails the person exists but the user sees "couldn't save". Acceptable (name optional) but report partial success or accept.

[MINOR] No view-model test for removing the LAST rule of a person (status -> confirmedNone, gate stays clear) in the Household tab; add one next to removeRule.

[NIT] `HouseholdTabPlaceholder` in TabPlaceholders.swift is now unused dead code; remove. `deleteAll` in-memory path runs repositories.deleteAll() then eraseStore deleting again (harmless duplication).

[QUESTION] FactText.origin omits the "{n}" count of C-153 (declared ASSUMPTION); is that owner-approved? Not a blocker.

## Tests vs Tests line
Reflect-back three answers (unit + UI), Forget, edit-stays-soft, add person -> gate, delete all -> S-01 all present at unit and UI level and assert repository state, not tautologies. UI tests not run here.

Round 1 of max 3. Tier S parts need re-review after the two MAJOR fixes.
