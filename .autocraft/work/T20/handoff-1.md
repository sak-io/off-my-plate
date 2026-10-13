# T20 developer handoff 1

```
HANDOFF
From: developer            To: pr-reviewer
Status: DONE
Summary: OMPData SwiftData persistence (SchemaV1, migration plan, DTOs, mappers, @ModelActor
  repositories, store config, deleteAllData) + TR-2 batch save on MealPlanRepository (Core).
  Not compiled locally (no Swift toolchain); `scripts/check-core.sh --lint-only` OK.
  macOS CI (`swift test --package-path Packages/Apple` and Core) is the verification of record.
Artifacts: local branch feat/t20 (commits 86a2bb5, fe64313, merge ca2028e, plus this handoff).
Next: lead pushes; CI (Linux + macOS) must be green; review (full review: plan approval persistence).
```

## What
- `Schema/SchemaV1.swift`: 12 `@Model` records (Household, Member, Rule, MealPlan, PantryItem, ShoppingItem,
  CookLog, Fact, LearningEvent, PromptState, ProcessedImport, Counter) in `SchemaV1: VersionedSchema`;
  `OMPMigrationPlan` with V1 only, no stages. CloudKit rules: no `.unique`, every property optional or
  defaulted, relationships optional (Household -> members/rules, cascade + explicit deletes). Enums as raw
  strings, sets as sorted `[String]`. `sequence` column keeps first-insertion order (matches InMemory);
  `sortIndex` keeps member/rule order. Defaults fail closed (member `unasked`, rule scope `household`).
- `Mapping/PlanContentDTO.swift`: `PlanContentDTO` v1 (meals blob; OMPData-owned format, does not reuse domain
  Codable; Dates as `timeIntervalSinceReferenceDate` for exact round trips) and `PantryDeductionsDTO` v1
  (cook-log deductions). Version header checked first: newer -> `unsupported...Version`, missing -> `unreadable...`.
- `Mapping/RecordMappers.swift`: `apply(domain)` / `domain()` per record. Unknown raw values, half-written
  approvals (some but not all `approval*` columns) and pantry rows with both/neither ref throw
  `PersistenceError` rather than guessing. Empty ids are never written. `MealPlan` is rebuilt through its public
  init (status/approval have `package` setters).
- `Repositories/SwiftDataRepositories.swift`: 8 `@ModelActor` actors implementing the OMPServices protocols;
  every write is one `ModelContext.commit` (save, or rollback + rethrow). Household `replace(with:)` deletes the
  old household + members + rules and inserts the new one in one save (at most one). `fetchAll()` exposed on the
  household repo for the contract test.
- `Store/PersistenceStore.swift`: `StoreLocation.inMemory` (unique name per container) / `.directory(URL)`
  (injectable; tests use temp dirs). `appDefault()` = Application Support/OffMyPlate. `cloudKitDatabase: .none`.
  Data Protection Complete on the directory and store/-wal/-shm (iOS only). `makeRepositories()`,
  `deleteAllData()` (all 12 record types in one save; container stays usable).
- **TR-2**: `MealPlanRepository.save(_ plans: [MealPlan])` added to the protocol (Core), InMemory impl + test;
  SwiftData impl is all-or-nothing (test: a batch with a bad meal id leaves the store unchanged).
- **TR-4**: golden JSON tests for PlanContentDTO v1 and PantryDeductionsDTO v1.

## Tests (Packages/Apple/Tests/OMPDataTests)
- `RepositoryContractTests`: every Core `InMemoryRepositoryTests` case, parameterised over in-memory AND on-disk,
  plus rich household/plan round trips, single household (no orphan members/rules), atomic household replace,
  atomic plan batch, deleteAll + `deleteAllData` (incl. imports/counters) then reuse.
- `PersistenceStoreTests`: reopen on disk persists all 8 entity types; in-memory isolation; directory creation;
  app default not in an App Group; file protection (iOS-only test); migration plan V1 only, 12 entities.
- `MapperRoundTripTests`: every record type and enum case (all Fact statements/subjects, all LearningEvent kinds,
  all ExplanationReasons), refusal cases, fail-closed defaults.
- `PlanContentDTOTests`: golden decode, golden-structure encode, determinism, version/unreadable/unknown values.
- `CloudKitRulesTests`: source lint (no `.unique`/`#Unique`; optional-or-defaulted; optional relationships),
  proven on planted violations.

## Deviations / questions (recommended defaults implemented)
- Q1 Store location: brief said "app-group container URL injectable"; ADR 0003/0011 (V3) say the store is in the
  app's own container, not the App Group. Implemented per ADR; the directory is injectable.
- Q2 `deleteAllData` deletes every record through a context instead of `ModelContainer.deleteAllData()`: its
  behaviour for live contexts/actors afterwards is unverified, and this keeps repositories usable (tested).
  Deleted SQLite pages may persist until reuse; switch if the reviewer prefers file destruction + reopen.
- Q3 Repositories hard-delete; `deletedAt` columns are reserved for sync tombstones (except Member's domain soft
  delete). Sync metadata `createdAt/updatedAt` are mapped where the domain has them, else left nil in v1.
- Q4 `ProcessedImportRecord` / `CounterRecord` have no repository yet (no protocol); T26/T17 add them.
- Size: ~1.85k source + ~1k test lines, over the 400-line guideline; mostly the 8 near-identical repositories
  and 12 mappers the task requires. Not split because the contract tests need all of them.
- Compile risk (no local toolchain): SwiftData API shapes used — `ModelConfiguration(_:schema:isStoredInMemoryOnly:
  allowsSave:groupContainer:cloudKitDatabase:)`, `ModelConfiguration(schema:url:allowsSave:cloudKitDatabase:)`,
  `ModelContainer(for:migrationPlan:configurations:)`, `@ModelActor`, `ModelContext.rollback()`, `fetchCount`.
