import Foundation
import OMPDomain
import OMPServices
import Testing

@testable import OMPFeatures

/// A wired Household tab over in-memory repositories (task T27): the app model, the live
/// settings backend and both view models.
@MainActor
struct SettingsEnv {
    let app: AppModel
    let repositories: Repositories
    let backend: LiveSettingsBackend
    let people: HouseholdViewModel
    let learning: LearningViewModel

    static func make(
        members: [Member], rules: [Rule] = [], facts: [Fact] = [], events: [LearningEvent] = [],
        householdRepository: (any HouseholdRepository)? = nil,
        eraseStore: (@Sendable () async throws -> Void)? = nil
    ) async -> SettingsEnv {
        let empty = Repositories.inMemory()
        var stored = household(members)
        stored.rules = rules
        let repositories = Repositories(
            household: householdRepository ?? InMemoryRepository<Household>([stored]), mealPlans: empty.mealPlans,
            pantry: empty.pantry, shopping: empty.shopping, cookLogs: empty.cookLogs,
            facts: InMemoryRepository<Fact>(facts), learningEvents: InMemoryRepository<LearningEvent>(events),
            promptStates: empty.promptStates)
        let clock = FixedClock(now: fixtureNow, timeZone: utc)
        let context = ServiceContext(
            repositories: repositories, clock: clock,
            library: PlanningLibrary(recipes: [], ingredients: [], restrictions: testRestrictions, contentVersion: "test"))
        let backend = LiveSettingsBackend(context: context, parser: SafetyTextParser(keywords: testKeywords), eraseStore: eraseStore)
        let app = AppModel(repositories: repositories, clock: clock)
        app.settingsBackend = backend
        await app.refresh()
        return SettingsEnv(
            app: app, repositories: repositories, backend: backend, people: HouseholdViewModel(app: app),
            learning: LearningViewModel(app: app))
    }
}

/// A hard rule from the test catalog.
func testRule(_ restriction: RestrictionID, for scope: RuleScope) -> Rule {
    let found = testRestrictions.first { $0.id == restriction }!
    return Rule(id: RuleID.generate(), scope: scope, restriction: found, createdAt: fixtureNow)
}

/// A soft fact with the stable id the learner would give it.
func softFact(
    _ statement: FactStatement, _ origin: FactOrigin, status: FactStatus = .active, confidence: Double = 1
) -> Fact {
    let key = FactKey(subject: .household, statement: statement)
    return Fact(
        id: FactLearner.stableID(for: key), statement: statement, origin: origin, confidence: confidence,
        status: status, createdAt: fixtureNow, updatedAt: fixtureNow)
}

/// Three "too long" re-rolls on weekdays in two ISO weeks before `fixtureNow` (a Monday): the
/// learner proposes "Quick dinners on weekdays" (AC-12.2).
func quickWeekdayEvents() -> [LearningEvent] {
    [3, 11, 12].enumerated().map { index, daysAgo in
        LearningEvent(
            id: LearningEventID("e\(index)"),
            kind: .rerolled(recipe: RecipeID("r"), slot: .dinner, reason: .tooLong),
            at: fixtureNow.addingTimeInterval(-Double(daysAgo) * 86_400))
    }
}

/// Collects the messages a model announced.
@MainActor
final class Announcements {
    var messages: [String] = []
}
