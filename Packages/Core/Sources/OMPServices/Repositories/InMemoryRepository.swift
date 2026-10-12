import Foundation
import OMPDomain

/// A thread-safe in-memory store of entities keyed by `id`, conforming to every repository
/// protocol for its entity type (tests, previews and Linux).
///
/// Entities are kept in insertion order; `save` replaces an existing entity in place, so
/// `fetchAll()` is deterministic. It never throws.
public actor InMemoryRepository<Entity: Identifiable & Sendable> where Entity.ID: Sendable {
    private var items: [Entity]

    public init(_ items: [Entity] = []) {
        self.items = items
    }

    public func fetch(id: Entity.ID) -> Entity? {
        items.first { $0.id == id }
    }

    public func fetchAll() -> [Entity] {
        items
    }

    /// Inserts `entity`, or replaces the stored entity with the same id in place.
    public func save(_ entity: Entity) {
        if let index = items.firstIndex(where: { $0.id == entity.id }) {
            items[index] = entity
        } else {
            items.append(entity)
        }
    }

    public func delete(id: Entity.ID) {
        items.removeAll { $0.id == id }
    }

    public func deleteAll() {
        items.removeAll()
    }
}

extension InMemoryRepository: HouseholdRepository where Entity == Household {
    public func fetch() -> Household? {
        items.first
    }
}

extension InMemoryRepository: MealPlanRepository where Entity == MealPlan {
    public func fetchSeries(_ seriesId: PlanSeriesID) -> [MealPlan] {
        items.filter { $0.seriesId == seriesId }.sorted { $0.revision < $1.revision }
    }
}

extension InMemoryRepository: PantryRepository where Entity == PantryItem {}

extension InMemoryRepository: ShoppingItemRepository where Entity == ShoppingItem {}

extension InMemoryRepository: CookLogRepository where Entity == CookLog {
    public func deleteCookLogs(before cutoff: Date) {
        items.removeAll { $0.cookedAt < cutoff }
    }
}

extension InMemoryRepository: FactRepository where Entity == Fact {}

extension InMemoryRepository: LearningEventRepository where Entity == LearningEvent {
    public func deleteEvents(before cutoff: Date) {
        items.removeAll { $0.at < cutoff }
    }
}

extension InMemoryRepository: PromptStateRepository where Entity == PromptState {}

public typealias InMemoryHouseholdRepository = InMemoryRepository<Household>
public typealias InMemoryMealPlanRepository = InMemoryRepository<MealPlan>
public typealias InMemoryPantryRepository = InMemoryRepository<PantryItem>
public typealias InMemoryShoppingItemRepository = InMemoryRepository<ShoppingItem>
public typealias InMemoryCookLogRepository = InMemoryRepository<CookLog>
public typealias InMemoryFactRepository = InMemoryRepository<Fact>
public typealias InMemoryLearningEventRepository = InMemoryRepository<LearningEvent>
public typealias InMemoryPromptStateRepository = InMemoryRepository<PromptState>
