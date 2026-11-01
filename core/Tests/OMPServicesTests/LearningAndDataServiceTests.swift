import Foundation
import OMPDomain
import OMPServices
import Testing

@Suite("LearningService: facts, reflect-back and counters (AC-12.x, T19)")
struct LearningServiceTests {
    private static let recipe: RecipeID = "b-poha"
    private static let key = FactKey(subject: .household, statement: .dislikesRecipe(recipe))

    /// Three skips of the same breakfast across two ISO weeks: enough to propose a fact.
    private func skipThreeTimes(_ env: ServicesBEnv) async throws {
        for (index, daysAgo) in [0.0, 8, 9].enumerated() {
            try await env.repositories.learningEvents.save(
                LearningEvent(
                    id: LearningEventID("skip-\(index)"), kind: .skipped(recipe: Self.recipe, slot: .breakfast),
                    at: ServicesFixture.now.addingTimeInterval(-daysAgo * 86_400)))
        }
    }

    @Test("repeated signals propose a soft fact; one reflect-back card is shown; Yes confirms it (AC-12.2, AC-12.3)")
    func proposeAndConfirm() async throws {
        let env = ServicesBEnv()
        #expect(try await env.learning.refresh().isEmpty)
        try await skipThreeTimes(env)

        let facts = try await env.learning.refresh()
        let fact = try #require(facts.first { $0.key == Self.key })
        #expect(fact.status == .proposed)
        #expect(fact.origin == .inferred)

        let card = try await env.learning.nextReflectBack()
        #expect(card?.key == Self.key)
        // Asking again shows the same open card without counting it twice.
        #expect(try await env.learning.nextReflectBack()?.key == Self.key)
        #expect(try await env.counters.value(of: CounterName.promptsShown) == 1)

        let answered = try await env.learning.answerReflectBack(Self.key, .yes)
        #expect(answered?.status == .active)
        #expect(answered?.origin == .confirmed)
        #expect(try await env.counters.value(of: CounterName.promptsAnswered) == 1)
        #expect(try await env.counters.value(of: CounterName.proposalsConfirmed) == 1)
        #expect(try await env.counters.value(of: CounterName.proposalsDismissed) == 0)
        let learned = try await env.learning.learned()
        #expect(learned.map(\.key) == [Self.key])
        #expect(try await env.learning.nextReflectBack() == nil)
    }

    @Test("Don't ask again dismisses for good and counts as dismissed (AC-12.3)")
    func dontAskAgain() async throws {
        let env = ServicesBEnv()
        try await skipThreeTimes(env)
        _ = try await env.learning.nextReflectBack()
        let answered = try await env.learning.answerReflectBack(Self.key, .dontAskAgain)
        #expect(answered?.status == .dismissed)
        #expect(answered?.suppressed == true)
        #expect(try await env.counters.value(of: CounterName.proposalsDismissed) == 1)
        env.clock.advance(days: 30)
        #expect(try await env.learning.nextReflectBack() == nil)
        #expect(try await env.learning.learned().isEmpty)
    }

    @Test("learning never creates or changes a rule, however strong the pattern (AC-12.4)")
    func learningNeverTouchesRules() async throws {
        let env = ServicesBEnv()
        try await env.base.onboardWithoutRules()
        let before = try await env.base.household()
        for index in 0..<10 {
            try await env.repositories.learningEvents.save(
                LearningEvent(
                    id: LearningEventID("skip-\(index)"), kind: .skipped(recipe: "d-dal", slot: .dinner),
                    at: ServicesFixture.now.addingTimeInterval(-Double(index) * 86_400)))
        }
        _ = try await env.learning.refresh()
        _ = try await env.learning.nextReflectBack()
        _ = try await env.learning.answerReflectBack(
            FactKey(subject: .household, statement: .dislikesRecipe("d-dal")), .yes)
        #expect(try await env.base.household() == before)
    }

    @Test("Forget removes the fact from What I've learned and unknown ids are reported (AC-12.5)")
    func forget() async throws {
        let env = ServicesBEnv()
        try await skipThreeTimes(env)
        let facts = try await env.learning.refresh()
        let fact = try #require(facts.first { $0.key == Self.key })
        let forgotten = try await env.learning.forget(fact.id)
        #expect(forgotten.status == .forgotten)
        #expect(try await env.learning.learned().isEmpty)
        let missing = await serviceError { _ = try await env.learning.forget("nope") }
        #expect(missing == .factNotFound("nope"))
    }

    @Test("editing a fact makes it stated and active (U8)")
    func restate() async throws {
        let env = ServicesBEnv()
        try await skipThreeTimes(env)
        let facts = try await env.learning.refresh()
        let fact = try #require(facts.first { $0.key == Self.key })
        let after = try await env.learning.restate(fact.id, subject: .household)
        let stated = try #require(after.first { $0.id == fact.id })
        #expect(stated.origin == .stated)
        #expect(stated.status == .active)
        let stored = try await env.repositories.facts.fetch(id: fact.id)
        #expect(stored == stated)
        let missing = await serviceError { _ = try await env.learning.restate("nope", subject: .household) }
        #expect(missing == .factNotFound("nope"))
    }
}

@Suite("DataService: Delete all data and pruning (AC-16.2, NFR Storage, T19)")
struct DataServiceTests {
    @Test("delete all leaves every repository, store and the inbox empty")
    func deleteAllLeavesNothing() async throws {
        let env = ServicesBEnv()
        let approved = try await env.base.approvedWeek()
        let meal = try #require(approved.meals.first { $0.recipeId != nil })
        _ = try await env.pantry.add(PantryItemInput(name: "rice", quantity: 1, unit: .kilogram, location: .shelf))
        _ = try await env.pantry.markCooked(plan: approved.id, meal: meal.id)
        _ = try await env.shopping.addManual(ShoppingItemInput(name: "Salt"))
        try await env.shopping.refresh()
        try await env.repositories.facts.save(
            Fact(
                id: "f1", statement: .staple("rice"), origin: .inferred, confidence: 0.5, status: .observing,
                createdAt: ServicesFixture.now, updatedAt: ServicesFixture.now))
        try await env.repositories.promptStates.save(PromptState(promptId: "lunchbox"))
        try await env.processed.insert("import-1", at: ServicesFixture.now)
        try await env.counters.increment(CounterName.promptsShown)
        let good = try ServicesBFixture.inboxFile(id: "import-2", items: [InboxImport.Item(name: "Rice")])
        await env.inbox.put(good.name, good.data)
        await env.inbox.put("import-bad.json", Data("x".utf8))
        _ = try await env.imports.drainInbox()  // import-bad.json goes to failed/
        await env.inbox.put("import-3.json", Data("{}".utf8))

        // Everything exists first, so the emptiness below proves something.
        let repositories = env.repositories
        #expect(try await repositories.household.fetch() != nil)
        #expect(try await repositories.mealPlans.fetchAll().count > 0)
        #expect(try await repositories.pantry.fetchAll().count > 0)
        #expect(try await repositories.shopping.fetchAll().count > 0)
        #expect(try await repositories.cookLogs.fetchAll().count > 0)
        #expect(try await repositories.facts.fetchAll().count > 0)
        #expect(try await repositories.learningEvents.fetchAll().count > 0)
        #expect(try await repositories.promptStates.fetchAll().count > 0)
        #expect(await env.inbox.failedNames().count > 0)

        try await env.data.deleteAll()

        #expect(try await repositories.household.fetch() == nil)
        #expect(try await repositories.mealPlans.fetchAll().isEmpty)
        #expect(try await repositories.pantry.fetchAll().isEmpty)
        #expect(try await repositories.shopping.fetchAll().isEmpty)
        #expect(try await repositories.cookLogs.fetchAll().isEmpty)
        #expect(try await repositories.facts.fetchAll().isEmpty)
        #expect(try await repositories.learningEvents.fetchAll().isEmpty)
        #expect(try await repositories.promptStates.fetchAll().isEmpty)
        #expect(try await env.processed.count() == 0)
        #expect(try await env.counters.all().isEmpty)
        #expect(await env.inbox.pendingNames().isEmpty)
        #expect(await env.inbox.failedNames().isEmpty)

        // Onboarding can start again, and deleting twice is harmless.
        try await env.data.deleteAll()
        try await env.base.households.createHousehold(adults: 1, children: 0)
    }

    @Test("the pruning cutoff is 12 calendar months back")
    func cutoff() {
        let env = ServicesBEnv()
        #expect(env.data.pruningCutoff() == Date(timeIntervalSince1970: 1_760_227_200))  // 2025-10-12T00:00Z
    }

    @Test("pruning removes cook logs, events and import ids older than 12 months and keeps the boundary")
    func pruningBoundary() async throws {
        let env = ServicesBEnv()
        let cutoff = env.data.pruningCutoff()
        let old = cutoff.addingTimeInterval(-1)
        for (index, date) in [old, cutoff, ServicesFixture.now].enumerated() {
            try await env.repositories.cookLogs.save(
                CookLog(
                    id: CookLogID("log-\(index)"), planId: "p", mealId: "m", recipeId: "r", cookedAt: date))
            try await env.repositories.learningEvents.save(
                LearningEvent(id: LearningEventID("event-\(index)"), kind: .cooked(recipe: "r"), at: date))
            try await env.processed.insert(InboxImportID("import-\(index)"), at: date)
        }
        // A fact is the household's current preference, not an old record: it stays.
        try await env.repositories.facts.save(
            Fact(
                id: "f1", statement: .staple("rice"), origin: .stated, confidence: 1, status: .active,
                createdAt: old, updatedAt: old))

        let used = try await env.data.prune()
        #expect(used == cutoff)
        let logs = try await env.repositories.cookLogs.fetchAll().map(\.id.rawValue)
        #expect(logs == ["log-1", "log-2"])
        let events = try await env.events().map(\.id.rawValue)
        #expect(events == ["event-1", "event-2"])
        #expect(try await env.processed.count() == 2)
        #expect(try await env.processed.contains("import-0") == false)
        #expect(try await env.processed.contains("import-1"))
        #expect(try await env.repositories.facts.fetchAll().count == 1)
    }
}
