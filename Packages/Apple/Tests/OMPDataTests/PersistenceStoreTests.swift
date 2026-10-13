import Foundation
import OMPDomain
import OMPServices
import SwiftData
import Testing

@testable import OMPData

@Suite("Persistence store")
struct PersistenceStoreTests {
    @Test("an on-disk store keeps every entity type after it is closed and reopened")
    func reopenPersists() async throws {
        let directory = TestStore.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let household = richHousehold()
        let plans = [richApprovedPlan(), fixturePlan("p2", series: "s1", revision: 3)]
        let pantry = [
            fixturePantryItem("a", quantity: 2),
            PantryItem(
                id: "b", item: .freeText("that green chutney"), quantity: 1, unit: .piece, location: .fridge,
                purchasedAt: fixtureNow, expiresOn: fixtureMonday.adding(days: 3), lastConfirmedAt: fixtureNow,
                source: .voice),
        ]
        let shopping = [
            ShoppingItem(
                id: "s1", key: "plan:rice:mass:toBuy", ingredientId: "rice", name: "Rice", quantity: 1.5,
                unit: .kilogram, aisle: .grainsAndFlours, checkedOff: true, origin: .plan, group: .checkYouHave)
        ]
        let cookLog = CookLog(
            id: "c1", planId: "p1", mealId: "m1", recipeId: "dal-tadka", cookedAt: fixtureNow,
            deductions: [
                PantryDeduction(pantryItemId: "a", quantity: 0.2, unit: .kilogram),
                PantryDeduction(pantryItemId: "b", quantity: 1, unit: .piece),
            ])
        let facts = allFacts()
        let events = allLearningEvents()
        let prompt = PromptState(promptId: "lunchbox", lastShownAt: fixtureNow, dismissedAt: nil, answeredAt: fixtureNow)

        do {
            let store = try PersistenceStore(location: .directory(directory))
            let repositories = store.makeRepositories()
            try await repositories.household.replace(with: household)
            try await repositories.mealPlans.save(plans)
            for item in pantry { try await repositories.pantry.save(item) }
            for item in shopping { try await repositories.shopping.save(item) }
            try await repositories.cookLogs.save(cookLog)
            for fact in facts { try await repositories.facts.save(fact) }
            for event in events { try await repositories.learningEvents.save(event) }
            try await repositories.promptStates.save(prompt)
        }
        #expect(FileManager.default.fileExists(atPath: PersistenceStore.storeURL(in: directory).path))

        let reopened = try PersistenceStore(location: .directory(directory)).makeRepositories()
        #expect(try await reopened.household.fetch() == household)
        #expect(try await reopened.mealPlans.fetchAll() == plans)
        #expect(try await reopened.pantry.fetchAll() == pantry)
        #expect(try await reopened.shopping.fetchAll() == shopping)
        #expect(try await reopened.cookLogs.fetchAll() == [cookLog])
        #expect(try await reopened.facts.fetchAll() == facts)
        #expect(try await reopened.learningEvents.fetchAll() == events)
        #expect(try await reopened.promptStates.fetchAll() == [prompt])
    }

    @Test("an in-memory store writes no store file and starts empty every time")
    func inMemoryStartsEmpty() async throws {
        let first = try PersistenceStore(location: .inMemory)
        try await first.makeRepositories().pantry.save(fixturePantryItem("a", quantity: 1))
        let second = try PersistenceStore(location: .inMemory)
        #expect(try await second.makeRepositories().pantry.fetchAll().isEmpty)
    }

    @Test("the directory location is created on demand and holds the store file")
    func directoryIsCreated() throws {
        let directory = TestStore.temporaryDirectory().appendingPathComponent("nested", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        let store = try PersistenceStore(location: .directory(directory))
        #expect(store.location == .directory(directory))
        #expect(PersistenceStore.storeURL(in: directory).lastPathComponent == "OffMyPlate.store")
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("the app default location is in Application Support, not an App Group container")
    func appDefaultLocation() throws {
        guard case .directory(let url) = try StoreLocation.appDefault() else {
            Issue.record("appDefault must be an on-disk location")
            return
        }
        #expect(url.lastPathComponent == "OffMyPlate")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Application Support")
        #expect(!url.path.contains("Group Containers"))
    }

    #if os(iOS)
    @Test("store files use Data Protection Complete")
    func fileProtectionComplete() async throws {
        let directory = TestStore.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try PersistenceStore(location: .directory(directory))
        try await store.makeRepositories().pantry.save(fixturePantryItem("a", quantity: 1))
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        #expect(attributes[.protectionKey] as? FileProtectionType == .complete)
    }
    #endif

    @Test("the migration plan has exactly SchemaV1 and no stages; the schema has the 12 records")
    func migrationPlanIsV1Only() {
        #expect(OMPMigrationPlan.schemas.count == 1)
        #expect(OMPMigrationPlan.schemas.map { ObjectIdentifier($0) } == [ObjectIdentifier(SchemaV1.self)])
        #expect(OMPMigrationPlan.stages.isEmpty)
        #expect(SchemaV1.models.count == 12)
        #expect(Schema(versionedSchema: SchemaV1.self).entities.count == 12)
    }
}
