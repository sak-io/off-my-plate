# W13 report: OMPWeb facade part 2

Branch `feat/w13` (CI branch `claude/ci-w13`). Extends `platforms/web/facade` (no `core/` change, no new dependency, same Wasm link flags as W03). All ops use the W03 envelope (`ctx` explicit on every call, canonical JSON, deterministic ids).

## Operations (new file `Sources/OMPWeb/OperationsKitchen.swift`)
| Area | Ops |
|---|---|
| Pantry | `pantry.list` (rows add derived `confidence` confident/low and `expired`), `pantry.search {query,limit?}`, `pantry.add`, `pantry.update`, `pantry.resolve`, `pantry.reconfirm`, `pantry.delete` |
| Mark cooked | `cook.propose {planId,mealId}`, `cook.mark {planId,mealId,amounts?}`. The core refuses any plan that is not effectively approved (`mark_cooked`, `details.reason` = `planNotApproved`, `blockedBySafety`, `alreadyCooked`, `mealNotFound`) |
| Shopping | `shopping.list/refresh/add/check/remove/boughtEverything/shareText` |
| Notes import | `import.parseText {text}` and `import.parseFile {base64}` (UTF-8 text only, `not_text` otherwise) return preview lines and save nothing; `import.confirm {destination:"shoppingList"\|"pantry", items}` writes the iOS inbox document and drains it with `ImportService` (staple learning events only; no access to rules) |
| Learning | `learning.list`, `learning.refresh`, `learning.reflectBack`, `learning.answer {factId,answer}`, `learning.confirm {factId}` (= answer yes), `learning.forget {factId}`. Fact confidence is rounded to 3 decimals in responses (learner uses exp/pow) |
| Data | `data.prune` (12-month cutoff), `data.deleteAll {confirmed:true}` (clears repositories, import records, counters, inbox; swaps in a fresh engine, ids restart; exempt from `clock_behind_state`) |

New error codes: `pantry_item_not_found`, `shopping_item_not_found`, `fact_not_found`, `fact_not_open`, `unknown_ingredient`, `not_text`; `mark_cooked` now carries `details.reason`.

## Bounds
Names 1...200 chars; amounts finite 0...1e9 (import items 0<q<=100000); search `limit` clamped 1...20; cook amounts <= 200; import items <= 500; pasted text/file <= 256 KiB (base64 <= 349,528 chars); expiry year 2000...2100; no client integer reaches arithmetic unclamped.

## State changes
- Snapshot format unchanged (version 1). Inbox, processed-import ids and counters are session-local; every import has a fresh id so nothing depends on old ids.
- Import validation: pantry/shopping amounts must be finite and <= 1e9. The date-shape check now requires digits, so typed names such as `abcd-ef-gh` no longer break `state.import` (bug found while adding free-text names).
- `clock_behind_state` also considers pantry confirmation times, cook logs, learning events and fact updates.

## Tests
`Tests/OMPWebTests/KitchenTests.swift` (18 tests): CRUD, confidence, search/resolve, bounds (Int64 min/max, 1e30, negatives), Mark cooked draft/approved/twice/blocked/amount bounds, shopping flow and bounds, import preview saves nothing, binary/oversized/malformed import, import never changes household or rules, forgotten fact stays forgotten across export/import, delete-all leaves every repository empty, prune cutoff, date-like names, absurd amounts in a state file. Transcript `Fixtures/transcript-w13.jsonl` + golden, replayed natively and under wasmtime (CI).

Golden caveat: the transcript never exports state while a non-forgotten fact exists (raw confidence in the snapshot comes from exp/pow).
