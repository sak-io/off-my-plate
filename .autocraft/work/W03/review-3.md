# W03 review 3 (delta 75c9255..b7ee2e1)
1. removeMember now runs before rule deletion; refusals (sole member, unknown id) throw before any change; failure midway leaves only soft-deleted-member rules, which cover nobody. OK.
2. RemoveMemberRulesTests assert exact remaining rules, gate open, and byte-identical state.export after refused removals. CI web-facade green on b7ee2e1.
3. Import dates parsed (LocalDate / ISODate), year 2000...2100, failure -> invalid_state; no force unwrap on input. OK.
4. No core/ change; UserConfirmation( in platforms/web only in ApprovalBridge.swift.
[NIT] Rules of a removed member persist if flag absent (core behaviour, tested).
VERDICT: APPROVED
