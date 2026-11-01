import Foundation
import OMPDomain
import OMPServices
import Testing

@testable import OMPFeatures

@Suite("AppModel inbox drain (T26)")
@MainActor
struct ImportDrainTests {
    private func makeModel(
        inbox: InMemoryInboxStorage, repositories: Repositories = .inMemory()
    ) -> AppModel {
        let clock = FixedClock(now: fixtureNow, timeZone: utc)
        let context = ServiceContext(
            repositories: repositories, clock: clock,
            library: PlanningLibrary(recipes: [], ingredients: [], restrictions: [], contentVersion: "test"))
        let model = AppModel(repositories: repositories, clock: clock)
        model.importService = ImportService(
            context: context, inbox: inbox, processedImports: InMemoryProcessedImportStore())
        return model
    }

    private func put(_ id: String, names: [String], into inbox: InMemoryInboxStorage) async throws {
        let item = try InboxImport(
            importId: InboxImportID(id), createdAt: fixtureNow, destination: .shoppingList,
            items: names.map { InboxImport.Item(name: $0) })
        let data = try item.encoded()
        await inbox.put(item.fileName, data)
    }

    @Test("draining merges the file into the shopping list and shows the C-111 toast")
    func mergesAndToasts() async throws {
        let inbox = InMemoryInboxStorage()
        let repositories = Repositories.inMemory()
        let model = makeModel(inbox: inbox, repositories: repositories)
        try await put("import-1", names: ["Curry leaves", "Jaggery"], into: inbox)

        await model.drainInbox()

        #expect(model.importToast == "Added 2 items from Notes.")
        #expect(try await repositories.shopping.fetchAll().map(\.name).sorted() == ["Curry leaves", "Jaggery"])
        #expect(await inbox.pendingNames().isEmpty)
    }

    @Test("one item reads 'Added 1 item from Notes.'")
    func singular() async throws {
        let inbox = InMemoryInboxStorage()
        let model = makeModel(inbox: inbox)
        try await put("import-1", names: ["Jaggery"], into: inbox)
        await model.drainInbox()
        #expect(model.importToast == "Added 1 item from Notes.")
    }

    @Test("an empty inbox shows no toast, and a second drain adds nothing")
    func emptyAndIdempotent() async throws {
        let inbox = InMemoryInboxStorage()
        let repositories = Repositories.inMemory()
        let model = makeModel(inbox: inbox, repositories: repositories)
        await model.drainInbox()
        #expect(model.importToast == nil)

        try await put("import-1", names: ["Jaggery"], into: inbox)
        await model.drainInbox()
        model.importToast = nil
        await model.drainInbox()
        #expect(model.importToast == nil)
        #expect(try await repositories.shopping.fetchAll().count == 1)
    }

    @Test("a corrupt file is quarantined without a toast and without touching the household")
    func corruptFile() async throws {
        let inbox = InMemoryInboxStorage()
        let repositories = Repositories.inMemory()
        let model = makeModel(inbox: inbox, repositories: repositories)
        await inbox.put("bad-1.json", Data("not json".utf8))
        await model.drainInbox()
        #expect(model.importToast == nil)
        #expect(await inbox.failedNames() == ["bad-1.json"])
        #expect(try await repositories.household.fetch() == nil)
    }

    @Test("without an import service draining does nothing")
    func noService() async {
        let model = AppModel(repositories: .inMemory(), clock: FixedClock(now: fixtureNow, timeZone: utc))
        await model.drainInbox()
        #expect(model.importToast == nil)
    }
}
