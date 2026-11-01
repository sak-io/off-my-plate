import Foundation
import OMPDomain
import OMPServices
import SwiftData

// SwiftData implementations of the OMPServices repository protocols (ADR 0003, task T20).
//
// Each repository is a `@ModelActor`: its `ModelContext` never leaves the actor, and only
// domain value types (all `Sendable`) cross the boundary. Behaviour matches the in-memory
// repositories exactly (the shared contract cases in `RepositoryContractTests`):
// - `save` is an upsert by id that keeps the entity's original position;
// - `fetchAll` returns entities in first-insertion order (`sequence` column);
// - every write is one `ModelContext.commit` (all or nothing).
// `delete(id:)` of a missing id is a no-op.

// MARK: Household

@ModelActor
public actor SwiftDataHouseholdRepository: HouseholdRepository {
    public func fetch() throws -> Household? {
        try fetchAll().first
    }

    /// Every stored household. The repository keeps at most one; exposed so tests can prove it.
    public func fetchAll() throws -> [Household] {
        let descriptor = FetchDescriptor<HouseholdRecord>(sortBy: [SortDescriptor(\.createdAt)])
        return try modelContext.fetch(descriptor).map { try household(from: $0) }
    }

    /// Deletes any stored household (with its members and rules) and stores `household`, in one
    /// save.
    public func replace(with household: Household) throws {
        try modelContext.commit {
            try deleteAllRecords()
            let record = HouseholdRecord(id: "")
            modelContext.insert(record)
            try record.apply(household)

            var members: [MemberRecord] = []
            for (index, member) in household.members.enumerated() {
                let memberRecord = MemberRecord(id: "")
                modelContext.insert(memberRecord)
                try memberRecord.apply(member, sortIndex: index)
                members.append(memberRecord)
            }
            var rules: [RuleRecord] = []
            for (index, rule) in household.rules.enumerated() {
                let ruleRecord = RuleRecord(id: "")
                modelContext.insert(ruleRecord)
                try ruleRecord.apply(rule, sortIndex: index)
                rules.append(ruleRecord)
            }
            record.members = members
            record.rules = rules
        }
    }

    public func deleteAll() throws {
        try modelContext.commit {
            try deleteAllRecords()
        }
    }

    private func household(from record: HouseholdRecord) throws -> Household {
        let members = try (record.members ?? []).sorted { $0.sortIndex < $1.sortIndex }.map { try $0.domain() }
        let rules = try (record.rules ?? []).sorted { $0.sortIndex < $1.sortIndex }.map { try $0.domain() }
        return try record.domain(members: members, rules: rules)
    }

    /// Children are deleted explicitly, not left to the cascade rule.
    private func deleteAllRecords() throws {
        for member in try modelContext.fetch(FetchDescriptor<MemberRecord>()) {
            modelContext.delete(member)
        }
        for rule in try modelContext.fetch(FetchDescriptor<RuleRecord>()) {
            modelContext.delete(rule)
        }
        for household in try modelContext.fetch(FetchDescriptor<HouseholdRecord>()) {
            modelContext.delete(household)
        }
    }
}

// MARK: MealPlan

@ModelActor
public actor SwiftDataMealPlanRepository: MealPlanRepository {
    public func fetch(id: MealPlanID) throws -> MealPlan? {
        try findRecord(id: id.rawValue)?.domain()
    }

    public func fetchAll() throws -> [MealPlan] {
        let descriptor = FetchDescriptor<MealPlanRecord>(sortBy: [SortDescriptor(\.sequence)])
        return try modelContext.fetch(descriptor).map { try $0.domain() }
    }

    public func fetchSeries(_ seriesId: PlanSeriesID) throws -> [MealPlan] {
        let raw = seriesId.rawValue
        let descriptor = FetchDescriptor<MealPlanRecord>(
            predicate: #Predicate { $0.seriesId == raw },
            sortBy: [SortDescriptor(\.revision), SortDescriptor(\.sequence)])
        return try modelContext.fetch(descriptor).map { try $0.domain() }
    }

    public func save(_ plan: MealPlan) throws {
        try save([plan])
    }

    /// Upserts every plan in one save (TR-2). If any plan cannot be written (for example an
    /// empty meal id), nothing is stored and the store is unchanged.
    public func save(_ plans: [MealPlan]) throws {
        try modelContext.commit {
            var nextSequence = try lastSequence() + 1
            var pending: [String: MealPlanRecord] = [:]
            for plan in plans {
                let raw = plan.id.rawValue
                let target: MealPlanRecord
                if let record = try pending[raw] ?? findRecord(id: raw) {
                    target = record
                } else {
                    target = MealPlanRecord(id: "")
                    target.sequence = nextSequence
                    nextSequence += 1
                    modelContext.insert(target)
                }
                try target.apply(plan)
                pending[raw] = target
            }
        }
    }

    public func delete(id: MealPlanID) throws {
        try modelContext.commit {
            if let record = try findRecord(id: id.rawValue) {
                modelContext.delete(record)
            }
        }
    }

    public func deleteAll() throws {
        try modelContext.commit {
            for record in try modelContext.fetch(FetchDescriptor<MealPlanRecord>()) {
                modelContext.delete(record)
            }
        }
    }

    private func findRecord(id: String) throws -> MealPlanRecord? {
        var descriptor = FetchDescriptor<MealPlanRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func lastSequence() throws -> Int {
        var descriptor = FetchDescriptor<MealPlanRecord>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.sequence ?? 0
    }
}

// MARK: Pantry

@ModelActor
public actor SwiftDataPantryRepository: PantryRepository {
    public func fetch(id: PantryItemID) throws -> PantryItem? {
        try findRecord(id: id.rawValue)?.domain()
    }

    public func fetchAll() throws -> [PantryItem] {
        let descriptor = FetchDescriptor<PantryItemRecord>(sortBy: [SortDescriptor(\.sequence)])
        return try modelContext.fetch(descriptor).map { try $0.domain() }
    }

    public func save(_ item: PantryItem) throws {
        try modelContext.commit {
            if let record = try findRecord(id: item.id.rawValue) {
                try record.apply(item)
            } else {
                let record = PantryItemRecord(id: "")
                record.sequence = try lastSequence() + 1
                modelContext.insert(record)
                try record.apply(item)
            }
        }
    }

    public func delete(id: PantryItemID) throws {
        try modelContext.commit {
            if let record = try findRecord(id: id.rawValue) {
                modelContext.delete(record)
            }
        }
    }

    public func deleteAll() throws {
        try modelContext.commit {
            for record in try modelContext.fetch(FetchDescriptor<PantryItemRecord>()) {
                modelContext.delete(record)
            }
        }
    }

    private func findRecord(id: String) throws -> PantryItemRecord? {
        var descriptor = FetchDescriptor<PantryItemRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func lastSequence() throws -> Int {
        var descriptor = FetchDescriptor<PantryItemRecord>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.sequence ?? 0
    }
}

// MARK: Shopping

@ModelActor
public actor SwiftDataShoppingItemRepository: ShoppingItemRepository {
    public func fetch(id: ShoppingItemID) throws -> ShoppingItem? {
        try findRecord(id: id.rawValue)?.domain()
    }

    public func fetchAll() throws -> [ShoppingItem] {
        let descriptor = FetchDescriptor<ShoppingItemRecord>(sortBy: [SortDescriptor(\.sequence)])
        return try modelContext.fetch(descriptor).map { try $0.domain() }
    }

    public func save(_ item: ShoppingItem) throws {
        try modelContext.commit {
            if let record = try findRecord(id: item.id.rawValue) {
                try record.apply(item)
            } else {
                let record = ShoppingItemRecord(id: "")
                record.sequence = try lastSequence() + 1
                modelContext.insert(record)
                try record.apply(item)
            }
        }
    }

    public func delete(id: ShoppingItemID) throws {
        try modelContext.commit {
            if let record = try findRecord(id: id.rawValue) {
                modelContext.delete(record)
            }
        }
    }

    public func deleteAll() throws {
        try modelContext.commit {
            for record in try modelContext.fetch(FetchDescriptor<ShoppingItemRecord>()) {
                modelContext.delete(record)
            }
        }
    }

    private func findRecord(id: String) throws -> ShoppingItemRecord? {
        var descriptor = FetchDescriptor<ShoppingItemRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func lastSequence() throws -> Int {
        var descriptor = FetchDescriptor<ShoppingItemRecord>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.sequence ?? 0
    }
}

// MARK: CookLog

@ModelActor
public actor SwiftDataCookLogRepository: CookLogRepository {
    public func fetch(id: CookLogID) throws -> CookLog? {
        try findRecord(id: id.rawValue)?.domain()
    }

    public func fetchAll() throws -> [CookLog] {
        let descriptor = FetchDescriptor<CookLogRecord>(sortBy: [SortDescriptor(\.sequence)])
        return try modelContext.fetch(descriptor).map { try $0.domain() }
    }

    public func save(_ log: CookLog) throws {
        try modelContext.commit {
            if let record = try findRecord(id: log.id.rawValue) {
                try record.apply(log)
            } else {
                let record = CookLogRecord(id: "")
                record.sequence = try lastSequence() + 1
                modelContext.insert(record)
                try record.apply(log)
            }
        }
    }

    /// Removes logs cooked strictly before `cutoff` (NFR Storage).
    public func deleteCookLogs(before cutoff: Date) throws {
        try modelContext.commit {
            let descriptor = FetchDescriptor<CookLogRecord>(predicate: #Predicate { $0.cookedAt < cutoff })
            for record in try modelContext.fetch(descriptor) {
                modelContext.delete(record)
            }
        }
    }

    public func deleteAll() throws {
        try modelContext.commit {
            for record in try modelContext.fetch(FetchDescriptor<CookLogRecord>()) {
                modelContext.delete(record)
            }
        }
    }

    private func findRecord(id: String) throws -> CookLogRecord? {
        var descriptor = FetchDescriptor<CookLogRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func lastSequence() throws -> Int {
        var descriptor = FetchDescriptor<CookLogRecord>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.sequence ?? 0
    }
}

// MARK: Fact

@ModelActor
public actor SwiftDataFactRepository: FactRepository {
    public func fetch(id: FactID) throws -> Fact? {
        try findRecord(id: id.rawValue)?.domain()
    }

    public func fetchAll() throws -> [Fact] {
        let descriptor = FetchDescriptor<FactRecord>(sortBy: [SortDescriptor(\.sequence)])
        return try modelContext.fetch(descriptor).map { try $0.domain() }
    }

    public func save(_ fact: Fact) throws {
        try modelContext.commit {
            if let record = try findRecord(id: fact.id.rawValue) {
                try record.apply(fact)
            } else {
                let record = FactRecord(id: "")
                record.sequence = try lastSequence() + 1
                modelContext.insert(record)
                try record.apply(fact)
            }
        }
    }

    public func delete(id: FactID) throws {
        try modelContext.commit {
            if let record = try findRecord(id: id.rawValue) {
                modelContext.delete(record)
            }
        }
    }

    public func deleteAll() throws {
        try modelContext.commit {
            for record in try modelContext.fetch(FetchDescriptor<FactRecord>()) {
                modelContext.delete(record)
            }
        }
    }

    private func findRecord(id: String) throws -> FactRecord? {
        var descriptor = FetchDescriptor<FactRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func lastSequence() throws -> Int {
        var descriptor = FetchDescriptor<FactRecord>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.sequence ?? 0
    }
}

// MARK: LearningEvent

@ModelActor
public actor SwiftDataLearningEventRepository: LearningEventRepository {
    public func fetchAll() throws -> [LearningEvent] {
        let descriptor = FetchDescriptor<LearningEventRecord>(sortBy: [SortDescriptor(\.sequence)])
        return try modelContext.fetch(descriptor).map { try $0.domain() }
    }

    public func save(_ event: LearningEvent) throws {
        try modelContext.commit {
            if let record = try findRecord(id: event.id.rawValue) {
                try record.apply(event)
            } else {
                let record = LearningEventRecord(id: "")
                record.sequence = try lastSequence() + 1
                modelContext.insert(record)
                try record.apply(event)
            }
        }
    }

    /// Removes events strictly before `cutoff` (NFR Storage).
    public func deleteEvents(before cutoff: Date) throws {
        try modelContext.commit {
            let descriptor = FetchDescriptor<LearningEventRecord>(predicate: #Predicate { $0.at < cutoff })
            for record in try modelContext.fetch(descriptor) {
                modelContext.delete(record)
            }
        }
    }

    public func deleteAll() throws {
        try modelContext.commit {
            for record in try modelContext.fetch(FetchDescriptor<LearningEventRecord>()) {
                modelContext.delete(record)
            }
        }
    }

    private func findRecord(id: String) throws -> LearningEventRecord? {
        var descriptor = FetchDescriptor<LearningEventRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func lastSequence() throws -> Int {
        var descriptor = FetchDescriptor<LearningEventRecord>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.sequence ?? 0
    }
}

// MARK: PromptState

@ModelActor
public actor SwiftDataPromptStateRepository: PromptStateRepository {
    public func fetch(id: PromptID) throws -> PromptState? {
        try findRecord(promptId: id.rawValue)?.domain()
    }

    public func fetchAll() throws -> [PromptState] {
        let descriptor = FetchDescriptor<PromptStateRecord>(sortBy: [SortDescriptor(\.sequence)])
        return try modelContext.fetch(descriptor).map { try $0.domain() }
    }

    public func save(_ state: PromptState) throws {
        try modelContext.commit {
            if let record = try findRecord(promptId: state.promptId.rawValue) {
                try record.apply(state)
            } else {
                let record = PromptStateRecord(promptId: "")
                record.sequence = try lastSequence() + 1
                modelContext.insert(record)
                try record.apply(state)
            }
        }
    }

    public func deleteAll() throws {
        try modelContext.commit {
            for record in try modelContext.fetch(FetchDescriptor<PromptStateRecord>()) {
                modelContext.delete(record)
            }
        }
    }

    private func findRecord(promptId: String) throws -> PromptStateRecord? {
        var descriptor = FetchDescriptor<PromptStateRecord>(predicate: #Predicate { $0.promptId == promptId })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func lastSequence() throws -> Int {
        var descriptor = FetchDescriptor<PromptStateRecord>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.sequence ?? 0
    }
}
