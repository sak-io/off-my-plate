import Foundation
import OMPDomain
import OMPServices
import Testing

@testable import OMPData

@Suite("SwiftData processed-import and counter stores")
struct LocalStoresTests {
    private let early = Date(timeIntervalSince1970: 1_000_000)
    private let late = Date(timeIntervalSince1970: 2_000_000)

    @Test("a processed import id is remembered once and counted once")
    func processedImportsRemembered() async throws {
        let store = try PersistenceStore(location: .inMemory).makeProcessedImportStore()
        let id = InboxImportID("import-1")
        #expect(try await store.contains(id) == false)
        try await store.insert(id, at: early)
        try await store.insert(id, at: late)
        #expect(try await store.contains(id))
        #expect(try await store.count() == 1)
    }

    @Test("pruning forgets only ids processed before the cutoff")
    func pruning() async throws {
        let store = try PersistenceStore(location: .inMemory).makeProcessedImportStore()
        try await store.insert(InboxImportID("old"), at: early)
        try await store.insert(InboxImportID("new"), at: late)
        try await store.deleteProcessed(before: Date(timeIntervalSince1970: 1_500_000))
        #expect(try await store.contains(InboxImportID("old")) == false)
        #expect(try await store.contains(InboxImportID("new")))
    }

    @Test("processed imports survive reopening an on-disk store")
    func processedImportsPersist() async throws {
        let directory = TestStore.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let store = try PersistenceStore(location: .directory(directory)).makeProcessedImportStore()
            try await store.insert(InboxImportID("kept"), at: early)
        }
        let reopened = try PersistenceStore(location: .directory(directory)).makeProcessedImportStore()
        #expect(try await reopened.contains(InboxImportID("kept")))
    }

    @Test("counters start at zero, increment per name and list all")
    func counters() async throws {
        let store = try PersistenceStore(location: .inMemory).makeCounterStore()
        #expect(try await store.value(of: CounterName.promptsShown) == 0)
        try await store.increment(CounterName.promptsShown)
        try await store.increment(CounterName.promptsShown)
        try await store.increment(CounterName.promptsAnswered)
        #expect(try await store.value(of: CounterName.promptsShown) == 2)
        #expect(try await store.all() == [CounterName.promptsShown: 2, CounterName.promptsAnswered: 1])
    }

    @Test("deleteAll empties both stores, and Delete all data does too")
    func deleteAll() async throws {
        let persistence = try PersistenceStore(location: .inMemory)
        let imports = persistence.makeProcessedImportStore()
        let counters = persistence.makeCounterStore()
        try await imports.insert(InboxImportID("a"), at: early)
        try await counters.increment("x")
        try await imports.deleteAll()
        try await counters.deleteAll()
        #expect(try await imports.count() == 0)
        #expect(try await counters.all().isEmpty)

        try await imports.insert(InboxImportID("b"), at: early)
        try await counters.increment("y")
        try await persistence.deleteAllData()
        #expect(try await imports.count() == 0)
        #expect(try await counters.value(of: "y") == 0)
    }

    @Test("an empty id or counter name is refused")
    func emptyKeysRefused() async throws {
        let persistence = try PersistenceStore(location: .inMemory)
        await #expect(throws: PersistenceError.self) {
            try await persistence.makeProcessedImportStore().insert(InboxImportID(""), at: early)
        }
        await #expect(throws: PersistenceError.self) {
            try await persistence.makeCounterStore().increment("")
        }
    }
}
