import Foundation
import OMPDomain
import OMPServices
import Testing

@testable import OMPFeatures

/// A household repository whose reads always fail.
private struct FailingHouseholdRepository: HouseholdRepository {
    struct Failure: Error {}
    func fetch() async throws -> Household? { throw Failure() }
    func replace(with household: Household) async throws { throw Failure() }
    func deleteAll() async throws { throw Failure() }
}

private func repositories(household: any HouseholdRepository) -> Repositories {
    let empty = Repositories.inMemory()
    return Repositories(
        household: household, mealPlans: empty.mealPlans, pantry: empty.pantry, shopping: empty.shopping,
        cookLogs: empty.cookLogs, facts: empty.facts, learningEvents: empty.learningEvents,
        promptStates: empty.promptStates)
}

@Suite("AppModel")
@MainActor
struct AppModelTests {
    private let clock = FixedClock(now: fixtureNow, timeZone: utc)

    @Test("Starts loading, then reports no household for an empty store")
    func emptyStore() async {
        let model = AppModel(repositories: .inMemory(), clock: clock)
        #expect(model.gateStatus == .loading)
        await model.refresh()
        #expect(model.gateStatus == .noHousehold)
        #expect(model.household == nil)
        #expect(model.membersNeedingAnswer.isEmpty)
    }

    @Test("An unasked member in the store raises the gate and is listed in stored order")
    func unaskedMember() async throws {
        let child1 = member(.child, 1, .unasked)
        let child2 = member(.child, 2, .unasked)
        let stored = household([member(.adult, 1, .confirmedNone), child1, child2])
        let model = AppModel(
            repositories: repositories(household: InMemoryRepository<Household>([stored])), clock: clock)
        await model.refresh()
        #expect(model.gateStatus == .unanswered([child1.id, child2.id]))
        #expect(model.membersNeedingAnswer.map(\.id) == [child1.id, child2.id])
    }

    @Test("Answering everyone and refreshing lowers the gate")
    func refreshAfterAnswer() async throws {
        var child = member(.child, 1, .unasked)
        let repo = InMemoryRepository<Household>([household([child])])
        let model = AppModel(repositories: repositories(household: repo), clock: clock)
        await model.refresh()
        #expect(model.gateStatus.showsGateCover)

        var updated = try #require(await repo.fetch())
        child.safetyStatus = .confirmedNone
        child.safetyConfirmedAt = fixtureNow
        updated.members = [child]
        await repo.replace(with: updated)
        await model.refresh()
        #expect(model.gateStatus == .clear)
        #expect(model.membersNeedingAnswer.isEmpty)
    }

    @Test("A failing read reports loadFailed rather than an empty household")
    func failingRead() async {
        let model = AppModel(repositories: repositories(household: FailingHouseholdRepository()), clock: clock)
        await model.refresh()
        #expect(model.gateStatus == .loadFailed)
    }

    @Test("A store that could not open stays loadFailed after refresh")
    func storeUnavailable() async {
        let model = AppModel.storeUnavailable(clock: clock)
        #expect(model.gateStatus == .loadFailed)
        await model.refresh()
        #expect(model.gateStatus == .loadFailed)
    }
}
