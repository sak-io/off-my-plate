import Foundation
import OMPDomain
import OMPServices
import Testing

@testable import OMPData

@Suite("Erase all data (AC-16.2)")
struct StoreEraseTests {
    private let marker = "zzEraseMarkerChutneyzz"

    @Test("eraseAllData leaves no record and no trace of the text in any store file")
    func eraseLeavesNoTrace() async throws {
        let directory = TestStore.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try PersistenceStore(location: .directory(directory))
        let repositories = store.makeRepositories()
        let item = PantryItem(
            id: "a", item: .freeText(marker), quantity: 1, unit: .piece, location: .fridge,
            purchasedAt: fixtureNow, expiresOn: fixtureMonday.adding(days: 3), lastConfirmedAt: fixtureNow,
            source: .voice)
        try await repositories.pantry.save(item)
        #expect(try await repositories.pantry.fetchAll().count == 1)

        try await store.eraseAllData()

        #expect(try await repositories.pantry.fetchAll().isEmpty)
        let needle = Data(marker.utf8)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(!files.isEmpty)
        for file in files {
            let bytes = try Data(contentsOf: file)
            #expect(bytes.range(of: needle) == nil, "Found the deleted text in \(file.lastPathComponent)")
        }

        // The same store takes new data afterwards.
        try await repositories.pantry.save(fixturePantryItem("after", quantity: 1))
        #expect(try await repositories.pantry.fetchAll().map(\.id) == ["after"])
    }

    @Test("eraseAllData on an in-memory store just empties it")
    func eraseInMemory() async throws {
        let store = try PersistenceStore(location: .inMemory)
        let repositories = store.makeRepositories()
        try await repositories.pantry.save(fixturePantryItem("a", quantity: 1))
        try await store.eraseAllData()
        #expect(try await repositories.pantry.fetchAll().isEmpty)
    }
}
