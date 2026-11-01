import Foundation
import OMPDomain
import OMPServices
import Testing

private let now = Date(timeIntervalSince1970: 1_791_763_200)  // 2026-10-12T00:00:00Z
private let monday = LocalDate(year: 2026, month: 10, day: 12)!

private func plan(_ id: MealPlanID, series: PlanSeriesID, revision: Int, status: PlanStatus = .draft) -> MealPlan {
    MealPlan(
        id: id, seriesId: series, revision: revision, weekStart: monday, status: status, meals: [],
        contentVersion: "seed-1", createdAt: now)
}

private func pantryItem(_ id: PantryItemID, quantity: Double) -> PantryItem {
    PantryItem(
        id: id, item: .ingredient("rice"), quantity: quantity, unit: .kilogram, location: .shelf,
        lastConfirmedAt: now, source: .manual)
}

@Suite("In-memory repositories")
struct InMemoryRepositoryTests {
    @Test("household: empty, replace, update, delete all")
    func householdCRUD() async throws {
        let repository: any HouseholdRepository = InMemoryHouseholdRepository()
        #expect(try await repository.fetch() == nil)

        var household = try Household.onboarding(id: "h", adults: 2, children: 1, now: now)
        try await repository.replace(with: household)
        #expect(try await repository.fetch() == household)

        household.settings.snacksEnabled = true
        try await repository.replace(with: household)
        #expect(try await repository.fetch()?.settings.snacksEnabled == true)

        try await repository.deleteAll()
        #expect(try await repository.fetch() == nil)
    }

    @Test("household store keeps at most one household: replacing with another id drops the old one")
    func singleHousehold() async throws {
        let repository = InMemoryHouseholdRepository()
        let first = try Household.onboarding(id: "h1", adults: 1, children: 0, now: now)
        let second = try Household.onboarding(id: "h2", adults: 2, children: 0, now: now)
        await repository.replace(with: first)
        await repository.replace(with: second)
        #expect(await repository.fetchAll().map(\.id) == ["h2"])
        #expect(await repository.fetch() == second)
    }

    @Test("meal plans: upsert by id, fetch by id, series in revision order, delete")
    func mealPlanCRUD() async throws {
        let repository: any MealPlanRepository = InMemoryMealPlanRepository()
        try await repository.save(plan("p2", series: "s1", revision: 2))
        try await repository.save(plan("p1", series: "s1", revision: 1, status: .approved))
        try await repository.save(plan("q1", series: "s2", revision: 1))

        #expect(try await repository.fetchAll().map(\.id) == ["p2", "p1", "q1"])
        #expect(try await repository.fetchSeries("s1").map(\.id) == ["p1", "p2"])
        #expect(try await repository.fetchSeries("none").isEmpty)
        #expect(try await repository.fetch(id: "p1")?.status == .approved)
        #expect(try await repository.fetch(id: "missing") == nil)

        try await repository.save(plan("p2", series: "s1", revision: 2, status: .discarded))
        #expect(try await repository.fetchAll().count == 3)
        #expect(try await repository.fetch(id: "p2")?.status == .discarded)

        try await repository.delete(id: "p2")
        #expect(try await repository.fetch(id: "p2") == nil)
        #expect(try await repository.fetchAll().map(\.id) == ["p1", "q1"])

        try await repository.deleteAll()
        #expect(try await repository.fetchAll().isEmpty)
    }

    @Test("meal plans: saving several plans at once upserts all of them in order")
    func mealPlanBatchSave() async throws {
        let repository: any MealPlanRepository = InMemoryMealPlanRepository()
        try await repository.save(plan("p1", series: "s1", revision: 1))
        try await repository.save([
            plan("p1", series: "s1", revision: 1, status: .superseded),
            plan("p2", series: "s1", revision: 2, status: .approved),
        ])
        #expect(try await repository.fetchAll().map(\.id) == ["p1", "p2"])
        #expect(try await repository.fetchSeries("s1").map(\.status) == [.superseded, .approved])
        try await repository.save([MealPlan]())
        #expect(try await repository.fetchAll().count == 2)
    }

    @Test("pantry: create, read, update, delete")
    func pantryCRUD() async throws {
        let repository: any PantryRepository = InMemoryPantryRepository()
        try await repository.save(pantryItem("a", quantity: 2))
        try await repository.save(pantryItem("b", quantity: 1))
        try await repository.save(pantryItem("a", quantity: 1.5))
        #expect(try await repository.fetchAll().map(\.id) == ["a", "b"])
        #expect(try await repository.fetch(id: "a")?.quantity == 1.5)
        try await repository.delete(id: "a")
        try await repository.delete(id: "not-there")
        #expect(try await repository.fetchAll().map(\.id) == ["b"])
    }

    @Test("shopping items: create, update check-off, delete")
    func shoppingCRUD() async throws {
        let repository: any ShoppingItemRepository = InMemoryShoppingItemRepository()
        var item = ShoppingItem(id: "s", key: "manual:soap", name: "Soap", aisle: .other, origin: .manual)
        try await repository.save(item)
        item.checkedOff = true
        try await repository.save(item)
        #expect(try await repository.fetch(id: "s")?.checkedOff == true)
        try await repository.delete(id: "s")
        #expect(try await repository.fetchAll().isEmpty)
    }

    @Test("cook logs: save, fetch, prune strictly before a cutoff")
    func cookLogCRUD() async throws {
        let repository: any CookLogRepository = InMemoryCookLogRepository()
        let old = CookLog(id: "old", planId: "p", mealId: "m1", recipeId: "r", cookedAt: now.addingTimeInterval(-60))
        let edge = CookLog(id: "edge", planId: "p", mealId: "m2", recipeId: "r", cookedAt: now)
        try await repository.save(old)
        try await repository.save(edge)
        #expect(try await repository.fetch(id: "old") == old)
        try await repository.deleteCookLogs(before: now)
        #expect(try await repository.fetchAll() == [edge])
    }

    @Test("facts: save, update status, delete")
    func factCRUD() async throws {
        let repository: any FactRepository = InMemoryFactRepository()
        var fact = Fact(
            id: "f", statement: .cuisineAffinity("southIndian"), origin: .stated, confidence: 1, status: .active,
            createdAt: now, updatedAt: now)
        try await repository.save(fact)
        fact.status = .dismissed
        try await repository.save(fact)
        #expect(try await repository.fetchAll().map(\.status) == [.dismissed])
        try await repository.delete(id: "f")
        #expect(try await repository.fetch(id: "f") == nil)
    }

    @Test("learning events: append in order, prune strictly before a cutoff")
    func learningEvents() async throws {
        let repository: any LearningEventRepository = InMemoryLearningEventRepository()
        let first = LearningEvent(id: "e1", kind: .cooked(recipe: "r"), at: now.addingTimeInterval(-1))
        let second = LearningEvent(id: "e2", kind: .importedItem(ingredient: "rice"), at: now)
        try await repository.save(first)
        try await repository.save(second)
        #expect(try await repository.fetchAll() == [first, second])
        try await repository.deleteEvents(before: now)
        #expect(try await repository.fetchAll() == [second])
    }

    @Test("prompt states: keyed by prompt id")
    func promptStates() async throws {
        let repository: any PromptStateRepository = InMemoryPromptStateRepository()
        try await repository.save(PromptState(promptId: "lunchbox", lastShownAt: now))
        try await repository.save(PromptState(promptId: "lunchbox", lastShownAt: now, dismissedAt: now))
        #expect(try await repository.fetchAll().count == 1)
        #expect(try await repository.fetch(id: "lunchbox")?.dismissedAt == now)
        #expect(try await repository.fetch(id: "other") == nil)
    }

    @Test("Repositories.inMemory starts empty and deleteAll empties every store")
    func deleteAllRepositories() async throws {
        let repositories = Repositories.inMemory()
        #expect(try await repositories.household.fetch() == nil)

        let household = try Household.onboarding(id: "h", adults: 1, children: 0, now: now)
        try await repositories.household.replace(with: household)
        try await repositories.mealPlans.save(plan("p", series: "s", revision: 1))
        try await repositories.pantry.save(pantryItem("a", quantity: 1))
        try await repositories.shopping.save(
            ShoppingItem(id: "s", key: "k", name: "Soap", aisle: .other, origin: .manual))
        try await repositories.cookLogs.save(
            CookLog(id: "c", planId: "p", mealId: "m", recipeId: "r", cookedAt: now))
        try await repositories.facts.save(
            Fact(
                id: "f", statement: .prefersQuickWeekday, origin: .stated, confidence: 1, status: .active,
                createdAt: now, updatedAt: now))
        try await repositories.learningEvents.save(LearningEvent(id: "e", kind: .cooked(recipe: "r"), at: now))
        try await repositories.promptStates.save(PromptState(promptId: "lunchbox"))

        try await repositories.deleteAll()

        #expect(try await repositories.household.fetch() == nil)
        #expect(try await repositories.mealPlans.fetchAll().isEmpty)
        #expect(try await repositories.pantry.fetchAll().isEmpty)
        #expect(try await repositories.shopping.fetchAll().isEmpty)
        #expect(try await repositories.cookLogs.fetchAll().isEmpty)
        #expect(try await repositories.facts.fetchAll().isEmpty)
        #expect(try await repositories.learningEvents.fetchAll().isEmpty)
        #expect(try await repositories.promptStates.fetchAll().isEmpty)
    }

    @Test("repositories created separately do not share state")
    func isolation() async {
        let first = InMemoryPantryRepository()
        let second = InMemoryPantryRepository([pantryItem("seeded", quantity: 1)])
        await first.save(pantryItem("a", quantity: 1))
        #expect(await first.fetchAll().map(\.id) == ["a"])
        #expect(await second.fetchAll().map(\.id) == ["seeded"])
    }
}
