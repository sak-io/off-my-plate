import Foundation
import OMPDomain

// Repository protocols (ADR 0003, ADR 0004). Use cases in OMPServices depend only on these.
// OMPData implements them with SwiftData on Apple platforms; `InMemoryRepository` implements
// them for tests and Linux. Every method is `async throws` so a SwiftData implementation can
// hop to its own actor and surface store errors. `save` is an upsert by id.

/// The single household on this device. The store holds at most one household.
public protocol HouseholdRepository: Sendable {
    func fetch() async throws -> Household?
    /// Stores `household` as *the* household, replacing whatever was stored before (even one
    /// with a different id). Named `replace` rather than `save` to make that explicit.
    func replace(with household: Household) async throws
    func deleteAll() async throws
}

/// Every plan revision of every series.
public protocol MealPlanRepository: Sendable {
    func fetch(id: MealPlanID) async throws -> MealPlan?
    func fetchAll() async throws -> [MealPlan]
    /// All revisions of a series, by ascending `revision`.
    func fetchSeries(_ seriesId: PlanSeriesID) async throws -> [MealPlan]
    func save(_ plan: MealPlan) async throws
    /// Upserts every plan in `plans` as one all-or-nothing unit (TR-2): either all of them are
    /// stored, or, when this throws, none of them changed. Approving a revision and
    /// superseding the previous one must use this, never two separate `save` calls.
    func save(_ plans: [MealPlan]) async throws
    func delete(id: MealPlanID) async throws
    func deleteAll() async throws
}

public protocol PantryRepository: Sendable {
    func fetch(id: PantryItemID) async throws -> PantryItem?
    func fetchAll() async throws -> [PantryItem]
    func save(_ item: PantryItem) async throws
    func delete(id: PantryItemID) async throws
    func deleteAll() async throws
}

public protocol ShoppingItemRepository: Sendable {
    func fetch(id: ShoppingItemID) async throws -> ShoppingItem?
    func fetchAll() async throws -> [ShoppingItem]
    func save(_ item: ShoppingItem) async throws
    func delete(id: ShoppingItemID) async throws
    func deleteAll() async throws
}

public protocol CookLogRepository: Sendable {
    func fetch(id: CookLogID) async throws -> CookLog?
    func fetchAll() async throws -> [CookLog]
    func save(_ log: CookLog) async throws
    /// Pruning (NFR Storage): removes logs cooked strictly before `cutoff`.
    func deleteCookLogs(before cutoff: Date) async throws
    func deleteAll() async throws
}

public protocol FactRepository: Sendable {
    func fetch(id: FactID) async throws -> Fact?
    func fetchAll() async throws -> [Fact]
    func save(_ fact: Fact) async throws
    func delete(id: FactID) async throws
    func deleteAll() async throws
}

public protocol LearningEventRepository: Sendable {
    func fetchAll() async throws -> [LearningEvent]
    func save(_ event: LearningEvent) async throws
    /// Pruning (NFR Storage): removes events strictly before `cutoff`.
    func deleteEvents(before cutoff: Date) async throws
    func deleteAll() async throws
}

public protocol PromptStateRepository: Sendable {
    func fetch(id: PromptID) async throws -> PromptState?
    func fetchAll() async throws -> [PromptState]
    func save(_ state: PromptState) async throws
    func deleteAll() async throws
}

/// All repositories, as the composition root wires them.
public struct Repositories: Sendable {
    public let household: any HouseholdRepository
    public let mealPlans: any MealPlanRepository
    public let pantry: any PantryRepository
    public let shopping: any ShoppingItemRepository
    public let cookLogs: any CookLogRepository
    public let facts: any FactRepository
    public let learningEvents: any LearningEventRepository
    public let promptStates: any PromptStateRepository

    public init(
        household: any HouseholdRepository,
        mealPlans: any MealPlanRepository,
        pantry: any PantryRepository,
        shopping: any ShoppingItemRepository,
        cookLogs: any CookLogRepository,
        facts: any FactRepository,
        learningEvents: any LearningEventRepository,
        promptStates: any PromptStateRepository
    ) {
        self.household = household
        self.mealPlans = mealPlans
        self.pantry = pantry
        self.shopping = shopping
        self.cookLogs = cookLogs
        self.facts = facts
        self.learningEvents = learningEvents
        self.promptStates = promptStates
    }

    /// Fresh, empty in-memory repositories (tests, previews, Linux).
    public static func inMemory() -> Repositories {
        Repositories(
            household: InMemoryRepository<Household>(),
            mealPlans: InMemoryRepository<MealPlan>(),
            pantry: InMemoryRepository<PantryItem>(),
            shopping: InMemoryRepository<ShoppingItem>(),
            cookLogs: InMemoryRepository<CookLog>(),
            facts: InMemoryRepository<Fact>(),
            learningEvents: InMemoryRepository<LearningEvent>(),
            promptStates: InMemoryRepository<PromptState>()
        )
    }

    /// Deletes every stored entity (part of "Delete all data", AC-16.2).
    public func deleteAll() async throws {
        try await household.deleteAll()
        try await mealPlans.deleteAll()
        try await pantry.deleteAll()
        try await shopping.deleteAll()
        try await cookLogs.deleteAll()
        try await facts.deleteAll()
        try await learningEvents.deleteAll()
        try await promptStates.deleteAll()
    }
}
