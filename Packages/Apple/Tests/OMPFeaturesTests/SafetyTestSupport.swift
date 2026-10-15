import Foundation
import OMPDomain
import OMPServices

@testable import OMPFeatures

let testRestrictions: [Restriction] = [
    Restriction(id: "peanuts", labelKey: "restriction.peanuts", excludedTags: [.peanut]),
    Restriction(id: "tree-nuts", labelKey: "restriction.treeNuts", excludedTags: [.treeNut]),
    Restriction(id: "milk", labelKey: "restriction.milk", excludedTags: [.milk]),
    Restriction(id: "beef", labelKey: "restriction.beef", excludedTags: [.beef]),
]

let testKeywords: [String: [RestrictionID]] = [
    "peanut": ["peanuts"],
    "beef": ["beef"],
    "nuts": ["peanuts", "tree-nuts"],
    "milk": ["milk"],
    "dairy": ["milk"],
]

/// Services over `repositories` with a tiny catalog and no recipes.
func makeSafetyServices(_ repositories: Repositories = .inMemory()) -> SafetyServices {
    let context = ServiceContext(
        repositories: repositories, clock: FixedClock(now: fixtureNow, timeZone: utc),
        library: PlanningLibrary(
            recipes: [], ingredients: [], restrictions: testRestrictions, contentVersion: "test"))
    return SafetyServices(context: context, parser: SafetyTextParser(keywords: testKeywords))
}

/// Counts how often a screen reported "done".
@MainActor
final class FinishCounter {
    var count = 0
}

enum TestFailure: Error { case missingHousehold }

func storedHousehold(_ services: SafetyServices) async throws -> Household {
    guard let household = try await services.household.household() else { throw TestFailure.missingHousehold }
    return household
}

/// A household repository whose writes fail.
struct WriteFailingHouseholdRepository: HouseholdRepository {
    struct Failure: Error {}
    let base: InMemoryRepository<Household>
    func fetch() async throws -> Household? { await base.fetch() }
    func replace(with household: Household) async throws { throw Failure() }
    func deleteAll() async throws { throw Failure() }
}
