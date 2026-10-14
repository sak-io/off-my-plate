import Foundation
import OMPDomain
import OMPServices
import Testing

@Suite("ImportService.drainInbox: idempotent merge, quarantine, staples only (AC-11.3, AC-11.5, ADR 0011, T19)")
struct ImportServiceTests {
    private static let items = [
        InboxImport.Item(name: "Rice", quantity: 2, unit: .kilogram),
        InboxImport.Item(name: "Curry leaves"),
    ]

    @Test("draining twice gives one merge")
    func drainTwiceMergesOnce() async throws {
        let env = ServicesBEnv()
        let file = try ServicesBFixture.inboxFile(id: "import-1", items: Self.items)
        await env.inbox.put(file.name, file.data)

        let first = try await env.imports.drainInbox()
        #expect(first.itemsAdded == 2)
        #expect(first.itemsMerged == 0)
        #expect(first.filesImported == 1)
        #expect(first.destinations == [.shoppingList])
        #expect(first.itemsTotal == 2)
        let listAfterFirst = try await env.repositories.shopping.fetchAll()
        #expect(listAfterFirst.count == 2)
        #expect(listAfterFirst.allSatisfy { $0.origin == .notesImport })
        #expect(await env.inbox.pendingNames().isEmpty)

        let second = try await env.imports.drainInbox()
        #expect(second == ImportSummary())
        #expect(try await env.repositories.shopping.fetchAll() == listAfterFirst)

        // The same file left behind (it could not be deleted) is removed, not merged again.
        await env.inbox.put(file.name, file.data)
        let third = try await env.imports.drainInbox()
        #expect(third.alreadyImported == 1)
        #expect(third.itemsAdded == 0)
        #expect(third.filesImported == 0)
        #expect(await env.inbox.pendingNames().isEmpty)
        #expect(try await env.repositories.shopping.fetchAll() == listAfterFirst)
        #expect(try await env.processed.count() == 1)
    }

    @Test("items merge into existing rows by ingredient, or by name for free text (AC-11.3)")
    func mergesByIngredient() async throws {
        let env = ServicesBEnv()
        let manual = try await env.shopping.addManual(ShoppingItemInput(name: "rice", quantity: 1, unit: .kilogram))
        let first = try ServicesBFixture.inboxFile(id: "import-a", items: Self.items)
        await env.inbox.put(first.name, first.data)
        let second = try ServicesBFixture.inboxFile(
            id: "import-b",
            items: [
                InboxImport.Item(name: "RICE", ingredientId: "rice", quantity: 500, unit: .gram),
                InboxImport.Item(name: "curry  leaves"),
            ])
        await env.inbox.put(second.name, second.data)

        let summary = try await env.imports.drainInbox()
        // import-a: rice merged into the manual row (1 kg + 2 kg), curry leaves added.
        // import-b: rice merged again (+ 0.5 kg), curry leaves merged by name.
        #expect(summary.itemsAdded == 1)
        #expect(summary.itemsMerged == 3)
        let rice = try await env.lines(for: ServicesBFixture.rice)
        #expect(rice.count == 1)
        #expect(rice.first?.id == manual.id)
        #expect(rice.first?.origin == .manual)
        #expect(rice.first?.unit == .kilogram)
        #expect(abs((rice.first?.quantity ?? 0) - 3.5) < 1e-9)
        let leaves = try await env.repositories.shopping.fetchAll().filter { $0.ingredientId == nil }
        #expect(leaves.count == 1)
        #expect(leaves.first?.name == "Curry leaves")
    }

    @Test("plan lines are never edited by an import: the item becomes its own row")
    func planLinesUntouched() async throws {
        let env = ServicesBEnv()
        _ = try await env.base.approvedWeek()
        let before = try await env.shopping.refresh().filter { $0.origin == .plan }
        try #require(!before.isEmpty)
        let file = try ServicesBFixture.inboxFile(
            id: "import-1", items: [InboxImport.Item(name: "rice", quantity: 1, unit: .kilogram)])
        await env.inbox.put(file.name, file.data)

        let summary = try await env.imports.drainInbox()
        #expect(summary.itemsAdded == 1)
        let after = try await env.repositories.shopping.fetchAll()
        #expect(after.filter { $0.origin == .plan } == before)
        #expect(after.filter { $0.origin == .notesImport }.count == 1)
    }

    @Test("a corrupt file goes to failed/ and the rest of the inbox is still imported (ADR 0011)")
    func corruptFileIsQuarantined() async throws {
        let env = ServicesBEnv()
        let good = try ServicesBFixture.inboxFile(id: "import-good", items: Self.items)
        await env.inbox.put(good.name, good.data)
        await env.inbox.put("import-garbage.json", Data("not json at all".utf8))
        await env.inbox.put("import-future.json", Data(#"{"schemaVersion":99}"#.utf8))
        // A readable import stored under another import's name is as untrustworthy as garbage.
        let other = try ServicesBFixture.inboxFile(id: "import-real", items: Self.items)
        await env.inbox.put("import-renamed.json", other.data)
        // Temporary files from an atomic write in progress are left alone.
        await env.inbox.put(".import-tmp.json.tmp", Data("partial".utf8))

        let summary = try await env.imports.drainInbox()
        #expect(summary.filesImported == 1)
        #expect(summary.quarantined.sorted() == ["import-future.json", "import-garbage.json", "import-renamed.json"])
        #expect(summary.stuck.isEmpty)
        #expect(await env.inbox.failedNames() == ["import-future.json", "import-garbage.json", "import-renamed.json"])
        #expect(await env.inbox.pendingNames() == [".import-tmp.json.tmp"])
        #expect(try await env.repositories.shopping.fetchAll().count == 2)
        // Quarantined files are not remembered as imported.
        #expect(try await env.processed.count() == 1)
    }

    @Test("a pantry import adds pantry items from Notes and merges repeats (AC-11.2 destination)")
    func pantryDestination() async throws {
        let env = ServicesBEnv()
        let first = try ServicesBFixture.inboxFile(
            id: "import-1", destination: .pantry,
            items: [
                InboxImport.Item(name: "Rice", quantity: 2, unit: .kilogram),
                InboxImport.Item(name: "Eggs", quantity: 6),
                InboxImport.Item(name: "Mango pickle"),
            ])
        await env.inbox.put(first.name, first.data)
        let summary = try await env.imports.drainInbox()
        #expect(summary.itemsAdded == 3)
        #expect(summary.destinations == [.pantry])
        let items = try await env.pantry.items()
        #expect(items.allSatisfy { $0.source == .notesImport && $0.lastConfirmedAt == ServicesFixture.now })
        let eggs = try #require(items.first { $0.item == .ingredient("eggs") })
        #expect(eggs.quantity == 6)
        #expect(eggs.unit == .piece)
        #expect(items.contains { $0.item == .freeText("Mango pickle") && $0.quantity == 1 })

        let again = try ServicesBFixture.inboxFile(
            id: "import-2", destination: .pantry, items: [InboxImport.Item(name: "rice", quantity: 500, unit: .gram)])
        await env.inbox.put(again.name, again.data)
        let repeated = try await env.imports.drainInbox()
        #expect(repeated.itemsMerged == 1)
        #expect(repeated.itemsAdded == 0)
        let rice = try #require(try await env.pantry.items().first { $0.item == .ingredient("rice") })
        #expect(abs(rice.quantity - 2.5) < 1e-9)
        #expect(rice.unit == .kilogram)
    }

    @Test("imports emit staple events only and never touch rules or safety status (AC-11.5, AC-12.4)")
    func importsAreStapleEvidenceOnly() async throws {
        let env = ServicesBEnv()
        try await env.base.onboardWithoutRules()
        _ = try await env.base.safety.addRule(RuleRequest(restriction: ServicesFixture.peanut, scope: .household))
        let householdBefore = try await env.base.household()

        let shopping = try ServicesBFixture.inboxFile(
            id: "import-1",
            items: [
                InboxImport.Item(name: "Rice", quantity: 2, unit: .kilogram),
                // Text that looks like a safety statement is just a name to the importer.
                InboxImport.Item(name: "peanut allergy - nuts are fine now"),
                InboxImport.Item(name: "Peanuts", ingredientId: "peanuts"),
            ])
        await env.inbox.put(shopping.name, shopping.data)
        let pantry = try ServicesBFixture.inboxFile(
            id: "import-2", destination: .pantry, items: [InboxImport.Item(name: "Curd")])
        await env.inbox.put(pantry.name, pantry.data)
        _ = try await env.imports.drainInbox()

        // Staple events for the resolved items only (rice, peanuts, curd).
        let kinds = try await env.events().map(\.kind)
        #expect(kinds.count == 3)
        let staples: Set<IngredientID> = Set(
            kinds.compactMap { kind -> IngredientID? in
                if case .importedItem(let ingredient) = kind { return ingredient }
                return nil
            })
        #expect(staples == ["rice", "peanuts", "curd"])

        // Rules, members and safety status are exactly as before.
        #expect(try await env.base.household() == householdBefore)

        // Learning from them can only ever produce soft staple facts.
        let facts = try await env.learning.refresh()
        #expect(
            facts.allSatisfy { fact in
                if case .staple = fact.statement { return true }
                return false
            })
        #expect(try await env.base.household() == householdBefore)
    }
}
