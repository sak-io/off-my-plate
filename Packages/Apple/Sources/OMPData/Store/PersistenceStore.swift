import Foundation
import OMPDomain
import OMPServices
import SwiftData

/// Where the store lives (ADR 0003).
public enum StoreLocation: Sendable, Hashable {
    /// RAM only: tests and previews. Every container gets its own, empty store.
    case inMemory
    /// A SQLite store in `directory` (created if needed, with Data Protection Complete).
    /// Tests pass a temporary directory.
    case directory(URL)

    /// The store file name inside the directory.
    public static let storeFileName = "OffMyPlate.store"

    /// The app's default: `Application Support/OffMyPlate/` in the app's **own** container.
    /// Not the App Group: the share extension never opens the store (ADR 0003, ADR 0011, V3).
    public static func appDefault(fileManager: FileManager = .default) throws -> StoreLocation {
        let support = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return .directory(support.appendingPathComponent("OffMyPlate", isDirectory: true))
    }
}

/// The SwiftData container plus factories for the repositories (ADR 0003, task T20).
///
/// `ModelContainer` is `Sendable`; `ModelContext` is not, so every context lives inside one of
/// the `@ModelActor` repositories and only domain value types cross actor boundaries.
public final class PersistenceStore: Sendable {
    public let container: ModelContainer
    public let location: StoreLocation

    /// Opens (or creates) the store at `location`, using `SchemaV1` and `OMPMigrationPlan`.
    /// CloudKit is explicitly off (ADR 0015).
    public init(location: StoreLocation) throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration: ModelConfiguration
        switch location {
        case .inMemory:
            // A unique name per container, so two in-memory stores never share data.
            configuration = ModelConfiguration(
                "omp-memory-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true,
                allowsSave: true, groupContainer: .none, cloudKitDatabase: .none)
        case .directory(let directory):
            try PersistenceStore.prepareDirectory(directory)
            configuration = ModelConfiguration(
                schema: schema, url: PersistenceStore.storeURL(in: directory), allowsSave: true,
                cloudKitDatabase: .none)
        }
        self.container = try ModelContainer(
            for: schema, migrationPlan: OMPMigrationPlan.self, configurations: [configuration])
        self.location = location
        if case .directory(let directory) = location {
            try PersistenceStore.protectStoreFiles(in: directory)
        }
    }

    /// The SQLite file for a store in `directory`.
    public static func storeURL(in directory: URL) -> URL {
        directory.appendingPathComponent(StoreLocation.storeFileName, isDirectory: false)
    }

    /// Fresh repository actors on this container (the composition root calls this once).
    public func makeRepositories() -> Repositories {
        Repositories(
            household: SwiftDataHouseholdRepository(modelContainer: container),
            mealPlans: SwiftDataMealPlanRepository(modelContainer: container),
            pantry: SwiftDataPantryRepository(modelContainer: container),
            shopping: SwiftDataShoppingItemRepository(modelContainer: container),
            cookLogs: SwiftDataCookLogRepository(modelContainer: container),
            facts: SwiftDataFactRepository(modelContainer: container),
            learningEvents: SwiftDataLearningEventRepository(modelContainer: container),
            promptStates: SwiftDataPromptStateRepository(modelContainer: container)
        )
    }

    /// Deletes every record of every type in one save, including processed imports and
    /// counters (AC-16.2). The container and existing repositories stay usable afterwards.
    /// Inbox files and the `UserDefaults` suite are the caller's part of "Delete all data".
    public func deleteAllData() async throws {
        try await StoreMaintenance(modelContainer: container).deleteAllRecords()
    }

    // MARK: File protection

    private static func prepareDirectory(_ directory: URL) throws {
        var attributes: [FileAttributeKey: Any] = [:]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.complete
        #endif
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: attributes)
    }

    /// Sets Data Protection Complete on the store and its SQLite side files (NFR Encryption).
    /// The app's entitlement already defaults new files to Complete (T02); this makes the store
    /// independent of that setting. Data Protection exists on iOS only.
    private static func protectStoreFiles(in directory: URL) throws {
        #if os(iOS)
        let fileManager = FileManager.default
        try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        let store = storeURL(in: directory).path
        for path in [store, store + "-wal", store + "-shm"] where fileManager.fileExists(atPath: path) {
            try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path)
        }
        #endif
    }
}

/// Store-wide maintenance on its own context.
@ModelActor
actor StoreMaintenance {
    func deleteAllRecords() throws {
        try modelContext.commit {
            // Children first, then their parents: no reliance on cascade rules.
            try deleteAll(MemberRecord.self)
            try deleteAll(RuleRecord.self)
            try deleteAll(HouseholdRecord.self)
            try deleteAll(MealPlanRecord.self)
            try deleteAll(PantryItemRecord.self)
            try deleteAll(ShoppingItemRecord.self)
            try deleteAll(CookLogRecord.self)
            try deleteAll(FactRecord.self)
            try deleteAll(LearningEventRecord.self)
            try deleteAll(PromptStateRecord.self)
            try deleteAll(ProcessedImportRecord.self)
            try deleteAll(CounterRecord.self)
        }
    }

    /// Number of records of every type (tests check "Delete all data" left nothing).
    func totalRecordCount() throws -> Int {
        let counts: [Int] = [
            try count(HouseholdRecord.self), try count(MemberRecord.self), try count(RuleRecord.self),
            try count(MealPlanRecord.self), try count(PantryItemRecord.self), try count(ShoppingItemRecord.self),
            try count(CookLogRecord.self), try count(FactRecord.self), try count(LearningEventRecord.self),
            try count(PromptStateRecord.self), try count(ProcessedImportRecord.self), try count(CounterRecord.self),
        ]
        return counts.reduce(0, +)
    }

    private func deleteAll<Model: PersistentModel>(_ type: Model.Type) throws {
        // Fetch and delete each object: batch deletes are not supported by every store type
        // (in-memory) and do not update objects already registered in other contexts.
        for record in try modelContext.fetch(FetchDescriptor<Model>()) {
            modelContext.delete(record)
        }
    }

    private func count<Model: PersistentModel>(_ type: Model.Type) throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<Model>())
    }
}

extension ModelContext {
    /// Runs `body` and saves; if either throws, rolls back every unsaved change and rethrows.
    /// This is the unit of work every repository write goes through (atomic, TR-2).
    func commit(_ body: () throws -> Void) throws {
        do {
            try body()
            try save()
        } catch {
            rollback()
            throw error
        }
    }
}
