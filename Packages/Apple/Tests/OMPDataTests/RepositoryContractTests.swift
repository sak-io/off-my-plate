import Foundation
import OMPDomain
import OMPServices
import Testing

@testable import OMPData

/// The in-memory repository contract (Core `InMemoryRepositoryTests`), run against SwiftData
/// in memory AND on disk (task T20).
@Suite("SwiftData repository contract")
struct RepositoryContractTests {
    @Test("household: empty, replace, update, delete all", arguments: StoreKind.allCases)
    func householdCRUD(kind: StoreKind) async throws {
        let fixture = try TestStore.make(kind)
        defer { fixture.cleanUp() }
        let repository: any HouseholdRepository = fixture.store.makeRepositories().household
        #expect(try await repository.fetch() == nil)

        var household = try Household.onboarding(id: "h", adults: 2, children: 1, now: fixtureNow)
        try await repository.replace(with: household)
        #expect(try await repository.fetch() == household)

        household.settings.snacksEnabled = true
        try await repository.replace(with: household)
        #expect(try await repository.fetch()?.settings.snacksEnabled == true)

        try await repository.deleteAll()
        #expect(try await repository.fetch() == nil)
    }

    @Test("household: every member and rule field round-trips, in order", arguments: StoreKind.allCases)
    func householdRichRoundTrip(kind: StoreKind) async throws {
        let fixture = try TestStore.make(kind)
        defer { fixture.cleanUp() }
        let repository = SwiftDataHouseholdRepository(modelContainer: fixture.store.container)
        let household = richHousehold()
        try await repository.replace(with: household)
        let stored = try await repository.fetch()
        #expect(stored == household)
        #expect(stored?.members.map(\.id) == ["c1", "a1", "a2"])
        #expect(stored?.rules.map(\.id) == ["r2", "r1"])
    }

    @Test(
        "household store keeps at most one household: replacing with another id drops the old one",
        arguments: StoreKind.allCases)
    func singleHousehold(kind: StoreKind) async throws {
        let fixture = try TestStore.make(kind)
        defer { fixture.cleanUp() }
        let repository = SwiftDataHouseholdRepository(modelContainer: fixture.store.container)
        let first = richHousehold()
        let second = try Household.onboarding(id: "h2", adults: 2, children: 0, now: fixtureNow)
        try await repository.replace(with: first)
        try await repository.replace(with: second)
        #expect(try await repository.fetchAll().map(\.id) == ["h2"])
        #expect(try await repository.fetch() == second)
        // The old household's members and rules went with it.
        let maintenance = StoreMaintenance(modelContainer: fixture.store.container)
        #expect(try await maintenance.totalRecordCount() == 1 + second.members.count)
    }

    @Test("household: a failed replace keeps the previous household", arguments: StoreKind.allCases)
    func householdReplaceIsAtomic(kind: StoreKind) async throws {
        let fixture = try TestStore.make(kind)
        defer { fixture.cleanUp() }
        let repository: any HouseholdRepository = fixture.store.makeRepositories().household
        let original = richHousehold()
        try await repository.replace(with: original)

        var broken = try Household.onboarding(id: "h2", adults: 1, children: 0, now: fixtureNow)
        broken.rules = [Rule(id: "", scope: .household, restriction: "peanut", excludedTags: [.peanut], createdAt: fixtureNow)]
        await #expect(throws: PersistenceError.emptyIdentifier(entity: "Rule")) {
            try await repository.replace(with: broken)
        }
        #expect(try await repository.fetch() == original)
    }

    @Test("meal plans: upsert by id, fetch by id, series in revision order, delete", arguments: StoreKind.allCases)
    func mealPlanCRUD(kind: StoreKind) async throws {
        let fixture = try TestStore.make(kind)
        defer { fixture.cleanUp() }
        let repository: any MealPlanRepository = fixture.store.makeRepositories().mealPlans
        try await repository.save(fixturePlan("p2", series: "s1", revision: 2))
        try await repository.save(fixturePlan("p1", series: "s1", revision: 1, status: .approved))
        try await repository.save(fixturePlan("q1", series: "s2", revision: 1))

        #expect(try await repository.fetchAll().map(\.id) == ["p2", "p1", "q1"])
        #expect(try await repository.fetchSeries("s1").map(\.id) == ["p1", "p2"])
        #expect(try await repository.fetchSeries("none").isEmpty)
        #expect(try await repository.fetch(id: "p1")?.status == .approved)
        #expect(try await repository.fetch(id: "missing") == nil)

        try await repository.save(fixturePlan("p2", series: "s1", revision: 2, status: .discarded))
        #expect(try await repository.fetchAll().count == 3)
        #expect(try await repository.fetch(id: "p2")?.status == .discarded)

        try await repository.delete(id: "p2")
        #expect(try await repository.fetch(id: "p2") == nil)
        #expect(try await repository.fetchAll().map(\.id) == ["p1", "q1"])

        try await repository.deleteAll()
        #expect(try await repository.fetchAll().isEmpty)
    }

    @Test("meal plans: content, status and approval round-trip", arguments: StoreKind.allCases)
    func mealPlanRichRoundTrip(kind: StoreKind) async throws {
        let fixture = try TestStore.make(kind)
        defer { fixture.cleanUp() }
        let repository: any MealPlanRepository = fixture.store.makeRepositories().mealPlans
        let plan = richApprovedPlan()
        try await repository.save(plan)
        #expect(try await repository.fetch(id: "p1") == plan)
    }

    @Test("meal plans: saving several plans at once upserts all of them in order", arguments: StoreKind.allCases)
    func mealPlanBatchSave(kind: StoreKind) async throws {
        let fixture = try TestStore.make(kind)
        defer { fixture.cleanUp() }
        let repository: any MealPlanRepository = fixture.store.makeRepositories().mealPlans
        try await repository.save(fixturePlan("p1", series: "s1", revision: 1))
        try await repository.save([
            fixturePlan("p1", series: "s1", revision: 1, status: .superseded),
            fixturePlan("p2", series: "s1", revision: 2, status: .approved),
        ])
        #expect(try await repository.fetchAll().map(\.id) == ["p1", "p2"])
        #expect(try await repository.fetchSeries("s1").map(\.status) == [.superseded, .approved])
        try await repository.save([MealPlan]())
        #expect(try await repository.fetchAll().count == 2)
    }

    @Test("meal plans: a batch with one unwritable plan stores none of them (TR-2)", arguments: StoreKind.allCases)
    func mealPlanBatchIsAtomic(kind: StoreKind) async throws {
        let fixture = try TestStore.make(kind)
        defer { fixture.cleanUp() }
        let repository: any MealPlanRepository = fixture.store.makeRepositories().mealPlans
        let approved = fixturePlan("p1", series: "s1", revision: 1, status: .approved)
        try await repository.save(approved)

        let badMeal = PlannedMeal(id: "", date: fixtureMonday, slot: .dinner, recipeId: "r", servings: [])
        await #expect(throws: PersistenceError.emptyIdentifier(entity: "PlannedMeal")) {
            try await repository.save([
                fixturePlan("p1", series: "s1", revision: 1, status: .superseded),
                fixturePlan("p2", series: "s1", revision: 2, status: .approved, meals: [badMeal]),
            ])
        }
        #expect(try await repository.fetchAll() == [approved])

        // The repository is still usable after the rollback.
        try await repository.save(fixturePlan("p3", series: "s1", revision: 3))
        #expect(try await repository.fetchAll().map(\.id) == ["p1", "p3"])
    }

    @Test("pantry: create, read, update, delete", arguments: StoreKind.allCases)
    func pantryCRUD(kind: StoreKind) async throws {
        let fixture = try TestStore.make(kind)
        defer { fixture.cleanUp() }
        let repository: any PantryRepository = fixture.store.makeRepositories().pantry
        try await repository.save(fixturePantryItem("a", quantity: 2))
        try await repository.save(fixturePantryItem("b", quantity: 1))
        try await repository.save(fixturePantryItem("a", quantity: 1.5))
        #expect(try await repository.fetchAll().map(\.id) == ["a", "b"])
        #expect(try await repository.fetch(id: "a")?.quantity == 1.5)
        try await repository.delete(id: "a")
        try await repository.delete(id: "not-there")
        #expect(try await repository.fetchAll().map(\.id) == ["b"])
    }

    @Test("shopping items: create, update check-off, delete", arguments: StoreKind.allCases)
    func shoppingCRUD(kind: StoreKind) async throws {
        let fixture = try TestStore.make(kind)
        defer { fixture.cleanUp() }
        let repository: any ShoppingItemRepository = fixture.store.makeRepositories().shopping
        var item = ShoppingItem(id: "s", key: "manual:soap", name: "Soap", aisle: .other, origin: .manual)
        try await repository.save(item)
        item.checkedOff = true
        try await repository.save(item)
        #expect(try await repository.fetch(id: "s")?.checkedOff == true)
        try await repository.delete(id: "s")
        #expect(try await repository.fetchAll().isEmpty)
    }

    @Test("cook logs: save, fetch, prune strictly before a cutoff", arguments: StoreKind.allCases)
    func cookLogCRUD(kind: StoreKind) async throws {
        let fixture = try TestStore.make(kind)
        defer { fixture.cleanUp() }
        let repository: any CookLogRepository = fixture.store.makeRepositories().cookLogs
        let old = CookLog(
            id: "old", planId: "p", mealId: "m1", recipeId: "r", cookedAt: fixtureNow.addingTimeInterval(-60),
            deductions: [PantryDeduction(pantryItemId: "a", quantity: 0.25, unit: .kilogram)])
        let edge = CookLog(id: "edge", planId: "p", mealId: "m2", recipeId: "r", cookedAt: fixtureNow)
        try await repository.save(old)
        try await repository.save(edge)
        #expect(try await repository.fetch(id: "old") == old)
        try await repository.deleteCookLogs(before: fixtureNow)
        #expect(try await repository.fetchAll() == [edge])
    }

    @Test("facts: save, update status, delete", arguments: StoreKind.allCases)
    func factCRUD(kind: StoreKind) async throws {
        let fixture = try TestStore.make(kind)
        defer { fixture.cleanUp() }
        let repository: any FactRepository = fixture.store.makeRepositories().facts
        var fact = Fact(
            id: "f", statement: .cuisineAffinity("southIndian"), origin: .stated, confidence: 1, status: .active,
            createdAt: fixtureNow, updatedAt: fixtureNow)
        try await repository.save(fact)
        fact.status = .dismissed
        try await repository.save(fact)
        #expect(try await repository.fetchAll().map(\.status) == [.dismissed])
        try await repository.delete(id: "f")
        #expect(try await repository.fetch(id: "f") == nil)
    }

    @Test("learning events: append in order, prune strictly before a cutoff", arguments: StoreKind.allCases)
    func learningEvents(kind: StoreKind) async throws {
        let fixture = try TestStore.make(kind)
        defer { fixture.cleanUp() }
        let repository: any LearningEventRepository = fixture.store.makeRepositories().learningEvents
        let first = LearningEvent(id: "e1", kind: .cooked(recipe: "r"), at: fixtureNow.addingTimeInterval(-1))
        let second = LearningEvent(id: "e2", kind: .importedItem(ingredient: "rice"), at: fixtureNow)
        try await repository.save(first)
        try await repository.save(second)
        #expect(try await repository.fetchAll() == [first, second])
        try await repository.deleteEvents(before: fixtureNow)
        #expect(try await repository.fetchAll() == [second])
    }

    @Test("prompt states: keyed by prompt id", arguments: StoreKind.allCases)
    func promptStates(kind: StoreKind) async throws {
        let fixture = try TestStore.make(kind)
        defer { fixture.cleanUp() }
        let repository: any PromptStateRepository = fixture.store.makeRepositories().promptStates
        try await repository.save(PromptState(promptId: "lunchbox", lastShownAt: fixtureNow))
        try await repository.save(PromptState(promptId: "lunchbox", lastShownAt: fixtureNow, dismissedAt: fixtureNow))
        #expect(try await repository.fetchAll().count == 1)
        #expect(try await repository.fetch(id: "lunchbox")?.dismissedAt == fixtureNow)
        #expect(try await repository.fetch(id: "other") == nil)
    }

    @Test("Repositories.deleteAll and PersistenceStore.deleteAllData empty every store", arguments: StoreKind.allCases)
    func deleteAllRepositories(kind: StoreKind) async throws {
        let fixture = try TestStore.make(kind)
        defer { fixture.cleanUp() }
        let repositories = fixture.store.makeRepositories()
        #expect(try await repositories.household.fetch() == nil)

        try await fillEveryStore(repositories)
        try await repositories.deleteAll()
        try await expectEmpty(repositories)

        // deleteAllData also clears records that have no repository yet (imports, counters).
        try await fillEveryStore(repositories)
        try await StoreMaintenance(modelContainer: fixture.store.container).insertExtraRecordsForTesting()
        try await fixture.store.deleteAllData()
        try await expectEmpty(repositories)
        #expect(try await StoreMaintenance(modelContainer: fixture.store.container).totalRecordCount() == 0)

        // The store and the existing repositories keep working afterwards.
        try await repositories.pantry.save(fixturePantryItem("after", quantity: 1))
        #expect(try await repositories.pantry.fetchAll().map(\.id) == ["after"])
    }

    @Test("repositories on separate stores do not share state")
    func isolation() async throws {
        let first = try TestStore.make(.inMemory)
        let second = try TestStore.make(.inMemory)
        try await first.store.makeRepositories().pantry.save(fixturePantryItem("a", quantity: 1))
        try await second.store.makeRepositories().pantry.save(fixturePantryItem("seeded", quantity: 1))
        #expect(try await first.store.makeRepositories().pantry.fetchAll().map(\.id) == ["a"])
        #expect(try await second.store.makeRepositories().pantry.fetchAll().map(\.id) == ["seeded"])
    }

    // MARK: Helpers

    private func fillEveryStore(_ repositories: Repositories) async throws {
        try await repositories.household.replace(with: richHousehold())
        try await repositories.mealPlans.save(richApprovedPlan())
        try await repositories.pantry.save(fixturePantryItem("a", quantity: 1))
        try await repositories.shopping.save(ShoppingItem(id: "s", key: "k", name: "Soap", aisle: .other, origin: .manual))
        try await repositories.cookLogs.save(CookLog(id: "c", planId: "p", mealId: "m", recipeId: "r", cookedAt: fixtureNow))
        for fact in allFacts() {
            try await repositories.facts.save(fact)
        }
        for event in allLearningEvents() {
            try await repositories.learningEvents.save(event)
        }
        try await repositories.promptStates.save(PromptState(promptId: "lunchbox"))
    }

    private func expectEmpty(_ repositories: Repositories) async throws {
        #expect(try await repositories.household.fetch() == nil)
        #expect(try await repositories.mealPlans.fetchAll().isEmpty)
        #expect(try await repositories.pantry.fetchAll().isEmpty)
        #expect(try await repositories.shopping.fetchAll().isEmpty)
        #expect(try await repositories.cookLogs.fetchAll().isEmpty)
        #expect(try await repositories.facts.fetchAll().isEmpty)
        #expect(try await repositories.learningEvents.fetchAll().isEmpty)
        #expect(try await repositories.promptStates.fetchAll().isEmpty)
    }
}

extension StoreMaintenance {
    /// Inserts one `ProcessedImportRecord` and one `CounterRecord` (no repositories yet).
    func insertExtraRecordsForTesting() throws {
        try modelContext.commit {
            modelContext.insert(ProcessedImportRecord(id: "import-1"))
            modelContext.insert(CounterRecord(name: "prompts-2026-W42"))
        }
    }
}
