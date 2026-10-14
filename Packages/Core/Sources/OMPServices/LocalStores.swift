import Foundation
import OMPDomain

/// Remembers which inbox imports were already merged, so a file that could not be deleted (or a
/// second drain) never merges twice (ADR 0011, AC-11.3). Wiped by "Delete all data".
public protocol ProcessedImportStore: Sendable {
    func contains(_ id: InboxImportID) async throws -> Bool
    func insert(_ id: InboxImportID, at date: Date) async throws
    func count() async throws -> Int
    /// Pruning: forgets ids processed strictly before `cutoff`.
    func deleteProcessed(before cutoff: Date) async throws
    func deleteAll() async throws
}

/// In-memory `ProcessedImportStore` (tests, previews).
public actor InMemoryProcessedImportStore: ProcessedImportStore {
    private var processed: [InboxImportID: Date] = [:]

    public init() {}

    public func contains(_ id: InboxImportID) -> Bool {
        processed[id] != nil
    }

    public func insert(_ id: InboxImportID, at date: Date) {
        processed[id] = date
    }

    public func count() -> Int {
        processed.count
    }

    public func deleteProcessed(before cutoff: Date) {
        processed = processed.filter { $0.value >= cutoff }
    }

    public func deleteAll() {
        processed.removeAll()
    }
}

/// Names of the on-device counters (ADR 0014). Counters never leave the device.
public enum CounterName {
    public static let promptsShown = "prompts.shown"
    public static let promptsAnswered = "prompts.answered"
    public static let proposalsConfirmed = "proposals.confirmed"
    public static let proposalsDismissed = "proposals.dismissed"
}

/// Local-only counters (AC-12.x, ADR 0014, NFR Analytics). Wiped by "Delete all data".
public protocol CounterStore: Sendable {
    func increment(_ name: String) async throws
    func value(of name: String) async throws -> Int
    func all() async throws -> [String: Int]
    func deleteAll() async throws
}

/// In-memory `CounterStore` (tests, previews).
public actor InMemoryCounterStore: CounterStore {
    private var counts: [String: Int] = [:]

    public init() {}

    public func increment(_ name: String) {
        counts[name, default: 0] += 1
    }

    public func value(of name: String) -> Int {
        counts[name] ?? 0
    }

    public func all() -> [String: Int] {
        counts
    }

    public func deleteAll() {
        counts.removeAll()
    }
}
