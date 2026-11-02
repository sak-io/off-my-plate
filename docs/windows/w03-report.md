# W03 report: OMPWeb JSON facade, approval bridge, Wasm entry

Branch `feat/w03` (CI branch `claude/ci-w03`). Package: `platforms/web/facade` (swift-tools 6.0, language mode 6, only dependency `../../../core` by path, Foundation only).
Scope: household, safety, plan, approval, state export/import. Pantry, shopping, import, learning, delete-all are W13 (not built).

## 1. Products
| Product | Kind | Purpose |
|---|---|---|
| `OMPWeb` | library | `FacadeSession.handle(Data) async -> Data`, `Facade.handle` (shared session), `Facade.handleSync` (no run loop needed), `TranscriptRunner` |
| `omp-web-cli` | executable (wasm command) | stdin: transcript lines; stdout: one response line per request (native and wasmtime) |
| `omp-web-wasm` | executable built as a **WASI reactor** | browser module, exports below |

**Reactor, not command (justification):** JS must call exports many times on one instance with state kept in memory. A command module runs `_start` once and exits; the reactor model gives `_initialize` (libc/Foundation constructors) and keeps the instance alive. Built with `-Xswiftc -Xclang-linker -Xswiftc -mexec-model=reactor` plus the W02 link flags `-z stack-size=4194304 --stack-first --global-base=4194304`.

**Sync driver:** the services are `async` (actors, `ServiceLock`). With no threads and no run loop, `Facade.handleSync` runs the request in a `Task(executorPreference:)` whose `TaskExecutor` queues jobs; the caller drains that queue on its own stack until the result exists (`SyncRunner.swift`). Default actors honour the task-executor preference, so the whole call completes on one thread, FIFO. Proven in CI under Node WASI (smoke test). If a job ever escaped to the global pool the call answers `executor_stalled` (Wasm) instead of hanging.

## 2. Wire format
Request: `{"op":"household.get","args":{...},"ctx":{"now":"2026-11-02T04:30:00Z","timeZone":"Asia/Kolkata","locale":"en-IN"}}`
Success: `{"ok":true,"result":...}`. Failure: `{"error":{"code":"...","message":"...","details":{...}?},"ok":false}`.
- `ctx` is required on every call (`missing_context` / `bad_context`); it sets the clock and zone of that call. Host defaults are never read. `now` is cut to whole seconds.
- Output is canonical JSON: sorted keys, no whitespace, dates ISO-8601 (UTC `Z`), sets sorted (Swift encodes sets in random order per process; the facade normalises them so native and Wasm are byte-identical).
- Ids are deterministic (`w1`, `w2`, ...); the counter is part of the exported state.
- Domain values are Swift's synthesized Codable: `LocalDate` is `"2026-11-02"`; enums with payloads look like `{"differentFromYesterday":{}}`, `{"quickWeekday":{"_0":"dinner"}}`, `RuleScope` `{"member":{"_0":"w4"}}`.
- Responses carry derived fields the UI must not recompute: `contentHash`, `effectivelyApproved`, `blockedMealIds`, `report` (validator report when the op produced one).

## 3. Operations
| Op | Args | Result |
|---|---|---|
| `meta.version` | | `{protocolVersion, stateVersion, coreVersion, contentVersion}` |
| `household.get` | | `{household?, gate}`; `gate` = `{status:"noHousehold"\|"open"\|"refused", reason?, memberIds?}` |
| `household.create` | `{adults, children}` | household view (everyone `unasked`) |
| `household.addMember` | `{role:"adult"\|"child", ageBand?}` | household view (gate refused until answered) |
| `household.setName` | `{memberId, name?}` | household view |
| `household.removeMember` | `{memberId}` | household view |
| `household.setAgeBand` | `{memberId, ageBand?}` | household view |
| `gate.status` | | `GateView` |
| `safety.catalog` | | `{restrictions:[{id,labelKey,excludedTags}]}` (chips, display order) |
| `safety.parse` | `{text}` | `{candidates:[{kind:"restriction",restriction,matchedText,memberHint?}\|{kind:"unmapped",text,memberHint?}]}`; saves nothing |
| `safety.confirm` | `{items:[{restriction?, unresolvedText?, scope?:{kind:"household"\|"member",memberId?}}]}` | `{household, gate, recheck}`; refuses `no_items`, `unresolved_items` |
| `safety.confirmNobody` | `{pendingItemCount}` (must be 0) | same; `nobody_not_allowed` otherwise; core refuses if rules exist (`safety_transition`) |
| `safety.confirmMember` | `{memberId, items}` (items may be empty) | same (adds the member's missing rules, then confirms; same sequence as iOS) |
| `safety.addRule` | `{item}` | same (R1 re-check) |
| `safety.removeRule` | `{ruleId, confirmed:true}` | same; `confirmation_required` without `confirmed` |
| `safety.reconfirm` | `{memberIds?}` | same |
| `safety.recheck` | | `RecheckView` (R1 + seed-version check) |
| `plan.current` | | `{seriesId?, working?, approved?, pendingDiff?, gate}` |
| `plan.generate` | `{absences?:[{memberId,date,slot}]}` | `PlanView` |
| `plan.get` / `plan.working` / `plan.approved` / `plan.pendingDiff` | `{planId}` / `{seriesId}` | `PlanView` / `PlanView?` / `PlanView?` / `DiffView?` |
| `plan.alternatives` | `{planId, mealId, reason?, limit?}` | `{alternatives:[{recipeId, reasons}]}` |
| `plan.swap` / `plan.reroll` / `plan.regenerate` | `{planId, mealId, recipeId}` / `{planId, mealId, reason?}` / `{planId, keepingLocked?}` | `PlanView` |
| `plan.lock` / `plan.unlock` | `{planId, mealId}` | `PlanView` (on an approved plan: a new draft revision) |
| `plan.discard` | `{planId}` | `PlanView` |
| `plan.approvalPreview` | `{planId}` | `{plan:PlanView, diff?, canApprove, gate?}`; records nothing |
| `plan.approve` | `{planId, shownContentHash, gesture:"confirm-button"}` | `{approved:PlanView, superseded?:PlanView}` |
| `state.export` | | `{snapshot}` |
| `state.import` | `{snapshot}` | `{imported:true, recheck}` |

Example (golden transcript, line 14 / 23):
```
-> {"op":"plan.alternatives","args":{"planId":"w6","mealId":"w6:2026-11-02:breakfast","limit":3},"ctx":{...}}
<- {"ok":true,"result":{"alternatives":[{"reasons":[{"differentFromYesterday":{}}],"recipeId":"appam-vegetable-stew"}, ...]}}
-> {"op":"plan.approve","args":{"planId":"w6","shownContentHash":"1466...0b91","gesture":"confirm-button"},"ctx":{...}}
<- {"ok":true,"result":{"approved":{"blockedMealIds":[],"contentHash":"1466...","effectivelyApproved":true,"plan":{"approval":{"approvedAt":"2026-11-02T04:30:00Z","approver":"thisDevice","contentHash":"1466..."},"status":"approved",...}}}}
```
The full replayable example is `platforms/web/facade/Fixtures/transcript.jsonl` with its output `transcript.golden.jsonl`.

## 4. Approval design
- `UserConfirmation()` is constructed in exactly one file, `Sources/OMPWeb/ApprovalBridge.swift`, inside the handler of `plan.approve`. `scripts/lint-safety.sh` allows that exact path (not a glob); fixtures prove a third file under `platforms/web` fails (`violation-user-confirmation-web-third-file`, `...-web-bridge-lookalike`, `...-web-alias`) and the bridge passes (`clean/`). A test also scans the facade sources and asserts only `ApprovalBridge.swift` mentions the type in code. CODEOWNERS covers the bridge and the facade `Package.swift`.
- `plan.approvalPreview` returns plan + SHA-256 content hash (core's `MealPlan.contentHash`) and records nothing.
- `plan.approve` requires (1) `gesture == "confirm-button"` (`approval_gesture_required`), (2) `shownContentHash == current hash` (`stale_preview`), then calls `PlanService.approve`, which still refuses while anyone is unasked, re-runs the independent validator against the current rules (`validation_failed`) and approves through `PlanLifecycle`.
- No other op can approve; there is no "approve all". Voice/text cannot approve (no voice on the web).
- **Honest limit** (also in the file header): a Wasm module cannot prove a human click. The guarantee is: one auditable door, the hash check (the person approved exactly what the sheet showed), and the UI wiring that W06 must test (only the sheet's button sends `plan.approve`; blocked plans disable it).
- State import is not a side door: an approved plan must carry an approval whose hash equals its content hash; drafts/discarded must carry none; then the R1 re-check runs on load (so a forged approval of unsafe content is flagged). A user who edits their own local data can still forge a matching hash; that is the same trust as the iOS store on the user's own device.

## 5. Memory protocol (browser module `omp-web-wasm.wasm`)
Exports: `memory`, `_initialize`, `omp_version() -> i32` (protocol version, 1), `omp_alloc(n) -> ptr`, `omp_free(ptr)`, `omp_call(ptr, n) -> m`, `omp_result_ptr() -> ptr`.
1. `instance = instantiate(module, {wasi_snapshot_preview1})`, call `_initialize()` once (e.g. Node `wasi.initialize(instance)`; in the browser a small WASI shim, e.g. `@bjorn3/browser_wasi_shim`, W04 decides).
2. For each request: `ptr = omp_alloc(len)`; copy UTF-8 bytes to `memory.buffer` at `ptr` (re-read `memory.buffer` after every call: memory can grow); `m = omp_call(ptr, len)`; `omp_free(ptr)`; read `m` bytes at `omp_result_ptr()`.
3. The result pointer is valid until the next `omp_call`; copy it out. `omp_call` returns `-1` only for an invalid buffer; every other failure is a JSON error document. Calls must not overlap (the call is synchronous, so JS cannot interleave them in one instance).
Reference client: `platforms/web/facade/wasm-smoke/smoke.mjs` (runs in CI).

## 6. Build and run
```
swift test --package-path platforms/web/facade                       # native, 34 tests
swift build --package-path platforms/web/facade --product omp-web-cli
.build/debug/omp-web-cli < platforms/web/facade/Fixtures/transcript.jsonl   # compare with transcript.golden.jsonl
# Wasm (SDK 6.2.4, checksum pinned in the workflow):
swift build --swift-sdk <wasm-sdk> --product omp-web-cli -c release -Xlinker -z -Xlinker stack-size=4194304 -Xlinker --stack-first -Xlinker --global-base=4194304
wasmtime run -W max-wasm-stack=8388608 .build/wasm32-unknown-wasip1/release/omp-web-cli.wasm < transcript.jsonl
swift build --swift-sdk <wasm-sdk> --product omp-web-wasm -c release -Xswiftc -Osize -Xswiftc -Xclang-linker -Xswiftc -mexec-model=reactor <same link flags> -Xlinker --strip-all
```
Transcript directives (no output line): `# comment`, `@capture NAME PATH` (value from the previous response, usable as `{{NAME}}`), `@expect ok` / `@expect error CODE`. The CLI exits 1 on a failed expectation.
Golden maintenance: run the native test with `OMP_GOLDEN_OUT=/path swift test --filter TranscriptTests`, review the output, copy it over `transcript.golden.jsonl`. CI prints the actual output (gzip+base64 annotations) only on a mismatch.

## 7. .wasm size
See section 9 (CI measurement): the release, `-Osize`, `--strip-all` reactor module is **54,377,241 bytes (about 52 MB; 19.3 MB gzip)** at commit 36d4aff. Well above what a PWA should ship. Section breakdown (CI, commit 68c2382): code 17.4 MB, **data 36.7 MB**, everything else < 0.3 MB. The data segment is almost certainly Foundation's ICU data linked statically. Options for W04/W12 (not done here, would touch core imports or tooling): serve brotli-compressed with a service-worker cache (one-time download), run `wasm-opt -Oz` in the release pipeline, and evaluate a FoundationEssentials-only build of the core.

## 8. Error codes
`bad_request`, `missing_context`, `bad_context`, `unknown_op`, `invalid_input`, `seed_unavailable`, `internal_error`, `executor_stalled`;
safety/household: `no_household`, `household_exists`, `household_size`, `gate_refused` (details `{reason, memberIds}`), `no_items`, `unresolved_items` (details `{texts}`), `nobody_not_allowed`, `confirmation_required`, `unknown_restriction`, `safety_transition`;
plan: `plan_not_found`, `not_working_plan`, `plan_not_draft`, `plan_closed`, `meal_not_found`, `meal_locked`, `recipe_not_offered`, `no_other_safe_recipe`, `open_draft_exists`, `clearance_not_valid`, `validation_failed` (details `{mealIds}`), `lifecycle_error`;
approval: `approval_gesture_required`, `stale_preview`;
state: `invalid_state`, `unsupported_state_version`; other service refusals: `mark_cooked`, `service_error`.

## 9. Tests and CI evidence
Swift Testing, `platforms/web/facade/Tests/OMPWebTests` (34 tests): approval door (gesture, hash, stale preview, unasked member, one-file check), gate bypass (unanswered member on every entry point, new member, swap to non-offered recipe, rule added after approval flags the approved plan, regenerate, every non-approve op leaves plans unapproved), safety flow (parse saves nothing, unresolved items, nobody, rule removal), household, envelope (20 malformed-request cases, invalid bytes, sync entry), state (round trip byte-identical, 10 garbage/tamper cases with no partial application), transcript replay vs golden.
CI `web-facade` (commits 36d4aff, 68c2382): native tests green; wasmtime replay of the transcript byte-identical to the golden (33 lines, 129,901 bytes); reactor builds; Node WASI smoke passes (alloc/call/result/free, gate, stale hash, wrong gesture, approve, export/import).

## 10. Deferred to W13 and later
Pantry, shopping list, notes/paste import, learning/facts, cuisines (`recordCuisines`), lunchbox/school lunches, Mark cooked, prompts, delete all data. The snapshot already contains all eight repositories (pantry, shopping, cook logs, facts, learning events, prompt states), so W13 ops will persist without a format change.

## 11. Open risks
- Size (section 7).
- Browser behaviour is only proven under Node WASI and wasmtime, not in Chrome/Edge (W04 first test).
- Debug builds of the reactor were not run in a browser; release only.
- The golden is produced by this code (reviewed by hand, plus expectation lines in the transcript); it protects against native/Wasm drift and accidental changes, not against a wrong plan algorithm (the core's own suites cover that).

## 12. Round-1 review fixes (pr-reviewer, TIER S)
| Item | What was done | Tests |
|---|---|---|
| MAJOR 1: integer overflow | `Limits.swift`: `household.create` bounds adults/children to 0...20 before the core adds them (`household_size`; values that do not fit the platform `Int` give `bad_request`); name <= 200, parse text <= 20,000, items <= 200 (unresolved text <= 2,000), absences <= 500, member ids <= 100, alternatives `limit` clamped 1...12, `pendingItemCount` is only compared. Import: plan `revision` 1...1,000,000, `idCounter` <= 1e9, every date or instant in the snapshot must be in years 2000...2100 (the core traps on `LocalDate` year 9999 + 6 days). | `LimitsTests`: Int64.max/min, Int32.max, 2147483648, negatives, 0, 21, 1e30, strings, nulls, boundaries (0+1, 12, 13, 20+20...); `ForgeryTests.structuralForgeriesAreRejected` (revision Int64.max, idCounter Int64.max, year 9999) |
| MAJOR 2 (a) | Snapshot with hash-consistent approved plan + household rules it violates: import succeeds but `recheck.blockedMealIds` and `plan.current.approved.blockedMealIds` are non-empty, the plan cannot be approved again, proposed revisions still go through the validator | `ForgeryTests.anApprovedPlanThatBreaksTheSnapshotsOwnRules...` |
| MAJOR 2 (b) | Unasked members, or answers older than 180 days: import is allowed (it is legitimate state) and the gate still refuses (`gate_refused`, `reconfirmationDue`) | `unansweredAndOverdueMembersStillBlockPlanningAfterImport` |
| MAJOR 2 (c) | Two `approved` plans in one series are **rejected** (`invalid_state`); a normal state has one (the older becomes `superseded`) | `twoApprovedPlansInOneSeriesAreRejected` |
| idCounter | The counter is raised to the highest `w<n>` id found anywhere in the snapshot (plan, meal, member, rule ids...), so new ids never overwrite stored entities | `theIdCounterIsRaisedAboveEveryIdInTheState` |
| Import consistency | Rejected (`invalid_state`): plans without a household, rules scoped to unknown members (deleted members count as known), duplicate ids, two approved plans per series, out-of-range revision/counter/dates | `structuralForgeriesAreRejected`, `StateTests` |
| ctx.now | Must be in years 2000...2100 (`bad_context`). Any op except `meta.version`, `state.export`, `state.import` is refused with `clock_behind_state` when `now` is earlier than the newest stored date (household, confirmations, plan creation/approval); import is refused when `now` is earlier than the snapshot. The host clock is otherwise trusted (it drives the 180-day re-confirmation). | `TimeTests.nowMustBeInAPlausibleRange`, `aClockBehindTheStoredDataIsRefused` |
| DST / America zones | America/Los_Angeles around the 2026-11-01 fall-back and 2026-03-08 spring-forward: week start for 00:30 PDT, 23:30 PST, 00:00 PST, 23:59 PDT. The same days are in `Fixtures/transcript-tz.jsonl` (expected week starts 2026-11-01, 2026-11-01, 2026-11-02, read from the golden), replayed natively AND by `omp-web-cli` under wasmtime in CI, so tz data on Wasm is proven. | `TimeTests.dayBoundariesAcrossADaylightSavingChange`, `TranscriptTests(transcript-tz)` |
| Request size | More than 8 MiB gives `request_too_large` (before parsing); `omp_alloc` also caps at 9 MiB | `oversizedRequestsAreRefused` |
| Duplicate keys | Rejected with `duplicate_key` anywhere in the request, including escaped spellings of the same key (`"a"` and `"\u0061"`); the same key in different objects is fine | `duplicateKeysAreRejected` |
| Memory protocol | `omp_alloc` returns 0 for sizes outside 1...9 MiB (negative, zero, absurd); allocations are tracked; `omp_free` ignores unknown pointers, double frees and the result buffer; `omp_call` returns -1 for a buffer omp_alloc did not hand out or a length beyond it, and -2 if a response would not fit Int32 | Node smoke test (alloc(-1), alloc(2147483647), unknown/freed buffers, double free, free of the result buffer, module still works afterwards) |
| Stuck job | `SyncRunner` abandons a call after a bounded number of drained jobs (5,000,000) or, if the queue runs dry, immediately (Wasm) or after a bounded wait (native), answering `executor_stalled`. Risk: the abandoned task may still hold the service-lock actor, so `Facade.handleSync` then calls `FacadeSession.recoverAfterStall()`, which rebuilds the services (new lock) over the same repositories; writes the abandoned call already made are kept. Nothing awaits outside the facade's own actors today, so a stall is not expected. | `LimitsTests.aStuckCallIsAbandonedNotHung` |

### QUESTION: iOS safety flow compared with the facade
Compared: `SafetyAnswerModel`, `OnboardingModel`, `SafetyServices`, `SettingsBackend`, `HouseholdViewModel`, against the core transitions in `SafetyStatusTransitions.swift`.
- `safety.confirmNobody`: iOS enables "No, nobody" only while the list is empty (`canChooseNobody`), then calls `confirmNobodyAvoidsAnything()`. Facade: client must send `pendingItemCount` (required; 0 only); the core independently refuses it when rules exist (`householdHasRules` -> `safety_transition`). Matches. For a single member iOS calls `confirmNothingToAvoid`/`confirmMemberAnswer` depending on coverage: `safety.confirmMember` does exactly that sequence.
- `safety.removeRule`: iOS shows a confirmation in the UI, then calls `removeRule`. The core moves a `stated` member with no remaining rules to `confirmedNone` and the service re-checks plans (R1) and the gate; the facade returns the new gate and recheck. The "are you sure" is the `confirmed:true` argument. Nothing else is done by iOS.
- Steps iOS performs that the facade does not (UI-only, by design): the candidates review/summary screen S-02b, the confirmation copy, per-row "Who?" menu and the reading-back of unrecognised words (the facade returns candidates; unresolved items are refused by `confirm`).
- One orchestration step was missing and is now available: onboarding "fewer people" removes the rules tagged only to a person before removing them (`OnboardingModel.applyCounts`). The core keeps such rules after a soft delete. Added `household.removeMember {removeOwnRules:true}`, which does the same in the same order. Raising a count is `household.addMember`. The member-variant "Remove {name}" on the safety screen does not remove rules in iOS either, so the default (false) matches it.
- Re-evaluating the gate after each change is done by the core service (`recheckOpenPlans`) and echoed in every response.
