# W03 review round 1 (pr-reviewer, TIER S)

Diff: claude/integration...feat/w03. CI (claude/ci-w03, 68c2382) taken as green; reviewed by reading and tracing.

## Verified (no finding)
- (1) UserConfirmation: only construction in non-test code is ApprovalBridge.swift (grep incl. alias/.init/extension: none elsewhere; fixtures are under scripts/tests). Gesture + hash checked before construction; PlanService.approve still runs gate + independent validator. No other op approves or clears blockedBySafety (the only blockedBySafety writes in the facade are reads). [PRAISE]
- (7) Lint: allow-list is an exact-path loop (`==`), ApprovalBridge2.swift lookalike, alias and third-file fixtures exist. CODEOWNERS covers bridge, facade Package.swift and the lint (`/scripts/lint-*.sh`). lint-safety scans core+platforms so the web tree is covered.
- (2) State import runs recheckOpenPlans (independent validator) on approved and draft plans and swaps the engine only after success (atomic). Approved plan with matching hash but a violating meal is flagged blockedBySafety, not trusted. Self-forging a matching hash is the same trust as editing the iOS SQLite file: acceptable for a single-user local app.
- (4)(6) Missing/invalid ctx, zone, non-ISO now give structured errors; invalid UTF-8 gives bad_request; messages do not leak paths.
- (5) Wasm protocol reads sane for a well-behaved host; result buffer replaced per call; executor-stall returns a structured error on WASI.
- (8) @expect/@capture failures are not masked: native test asserts `failures.isEmpty` and compares bytes with golden; CLI exits 1 on failures.
- (9) Workflow: pinned checkout SHA, pinned SDK/wasmtime checksums, no secrets, contents:read, byte-compare with golden.

## Findings

[MAJOR] Crash on arithmetic overflow in household.create (Operations.swift `household.create`, core Household.onboarding `adults + children`). `{"adults":9223372036854775807,"children":1}` (or 2147483647 twice on wasm32, where Int is 32-bit) traps at `adults + children` before the size check. A trap kills the whole Wasm instance and the native process; the brief and the task require structured errors, not crashes. Fix in the facade: reject negative or > some small bound (e.g. 0...20) per field before calling the service, return `household_size`/`invalid_input`; add a test with Int64.max, Int32.max and negatives. Same audit for every other `Int` argument (`pendingItemCount` is only compared; `limit` is clamped, fine).

[MAJOR] No test for the import-forgery path that matters most. StateTests only tests structural rejects (bad hash, missing approval, draft with approval). Nothing tests that a snapshot with a hash-consistent approved plan whose meal violates a rule in the same snapshot's household is imported with `blockedBySafety` set and a proposed draft (or refusal), i.e. that the claim in (2) holds; nor a household snapshot with members unanswered/overdue then `plan.generate` refused after import. Add: export, edit household rules to forbid a restriction used by the approved plan (keep hash), import, assert recheck.blockedMealIds non-empty and plan.current.approved.blockedMealIds non-empty and `plan.approve` of any revision still goes through the validator.

[MINOR] State import: `idCounter` is not checked against ids in use. A crafted/corrupted snapshot with a low counter makes later `w<n>` ids collide with existing plan/member ids, and `save` overwrites (an approved plan can be replaced by a new draft with the same id; members/rules can alias). Validate `idCounter >= max numeric suffix of all `w<n>` ids` or reject.

[MINOR] State import accepts plans with no household (recheck returns early) and household rules/scopes referencing unknown members, and several approved plans in one series (activeApprovedPlan then silently picks the highest revision). Reject plans-without-household and rules whose member scope is unknown; reject >1 effectively-approved plan per series, or at least cover with a test.

[MINOR] ctx.now has no range check (year 0000 / 9999 accepted) and nothing guards a `now` earlier than stored confirmation dates (negative elapsed in the 180-day check). Suggest a sane window (e.g. 2020...2100) with `bad_context`; document that the host clock is trusted for the 180-day re-confirmation. America/* zones are not exercised on the Wasm build (only Asia/Kolkata): add one transcript/test with America/New_York around DST change for week-start math, or note timezone data availability on Wasm.

[MINOR] No input size cap (omp_call length and JSON depth/size). Foundation's decoder limits depth, but a multi-MB request still allocates freely; add a cap (e.g. 8 MiB) returning `request_too_large`. Duplicate JSON keys: behaviour unspecified (last wins); say so or reject.

[MINOR] Memory protocol: `omp_free` on the result pointer (or a double free by the host) corrupts the heap in `ResultStore.replace`; negative `omp_alloc` size silently returns 1 byte (host would then write n bytes). Document, and make `omp_alloc` return null for size <= 0 and the smoke test cover alloc(-1) and omp_call(len<0) returning -1.

[MINOR] SyncRunner: if a job ever never resumes, the WASI path returns executor_stalled but the suspended task still holds the service lock, so every later call stalls. Acceptable today (no external awaits) but note it in the report.

[NIT] `omp_call` returns Int32 from a `Data` count; fine below 2 GiB, but add an explicit guard.

[QUESTION] Semantic drift vs iOS (SafetyServices/OnboardingModel): `safety.confirmNobody` trusts the client's `pendingItemCount` and `safety.removeRule` trusts `confirmed`; the core refuses "nobody" when rules exist (SafetyFlowTests nobodyContradictingStoredRules covers). Confirm the iOS flow has no extra step (e.g. member-level 'reconfirm' ordering) the facade omits. Not blocking.

[NIT] Golden is produced by the same code; it protects native==Wasm equality and regressions, not semantics. Semantics are covered by @expect lines and GateBypass/ApprovalDoor tests, which are specific (error codes asserted). Fine.

VERDICT: CHANGES REQUESTED
