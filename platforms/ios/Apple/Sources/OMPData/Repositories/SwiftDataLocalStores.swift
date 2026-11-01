import Foundation
import OMPDomain
import OMPServices
import SwiftData

// SwiftData implementations of the two small local stores of OMPServices (ADR 0011, ADR 0014,
// task T26): imported inbox ids and on-device counters. Both are wiped by "Delete all data"
// (`PersistenceStore.deleteAllData` and the `deleteAll` methods here).

/// Remembers which inbox imports were merged (idempotent drain, AC-11.3).
@ModelActor
public actor SwiftDataProcessedImportStore: ProcessedImportStore {
    public func contains(_ id: InboxImportID) throws -> Bool {
        try findRecord(id: id.rawValue) != nil
    }

    public func insert(_ id: InboxImportID, at date: Date) throws {
        let raw = try Mapping.id(id.rawValue, entity: "ProcessedImport")
        try modelContext.commit {
            if let record = try findRecord(id: raw) {
                record.processedAt = date
                record.updatedAt = date
            } else {
                let record = ProcessedImportRecord(id: raw)
                record.processedAt = date
                record.createdAt = date
                record.updatedAt = date
                modelContext.insert(record)
            }
        }
    }

    public func count() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<ProcessedImportRecord>())
    }

    public func deleteProcessed(before cutoff: Date) throws {
        try modelContext.commit {
            let descriptor = FetchDescriptor<ProcessedImportRecord>(
                predicate: #Predicate { $0.processedAt < cutoff })
            for record in try modelContext.fetch(descriptor) {
                modelContext.delete(record)
            }
        }
    }

    public func deleteAll() throws {
        try modelContext.commit {
            for record in try modelContext.fetch(FetchDescriptor<ProcessedImportRecord>()) {
                modelContext.delete(record)
            }
        }
    }

    private func findRecord(id: String) throws -> ProcessedImportRecord? {
        var descriptor = FetchDescriptor<ProcessedImportRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

/// Local-only counters (never leave the device, ADR 0014).
@ModelActor
public actor SwiftDataCounterStore: CounterStore {
    public func increment(_ name: String) throws {
        let key = try Mapping.id(name, entity: "Counter")
        try modelContext.commit {
            if let record = try findRecord(name: key) {
                record.count += 1
            } else {
                let record = CounterRecord(name: key)
                record.count = 1
                modelContext.insert(record)
            }
        }
    }

    public func value(of name: String) throws -> Int {
        try findRecord(name: name)?.count ?? 0
    }

    public func all() throws -> [String: Int] {
        var result: [String: Int] = [:]
        for record in try modelContext.fetch(FetchDescriptor<CounterRecord>()) {
            result[record.name] = record.count
        }
        return result
    }

    public func deleteAll() throws {
        try modelContext.commit {
            for record in try modelContext.fetch(FetchDescriptor<CounterRecord>()) {
                modelContext.delete(record)
            }
        }
    }

    private func findRecord(name: String) throws -> CounterRecord? {
        var descriptor = FetchDescriptor<CounterRecord>(predicate: #Predicate { $0.name == name })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
