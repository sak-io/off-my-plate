import Foundation
import OMPDomain

/// "Delete all data" and pruning (AC-16.2, NFR Storage, ADR 0014; task T19).
public final class DataService: Sendable {
    /// Cook logs, learning events and import records older than this many months are pruned.
    public static let retentionMonths = 12

    let context: ServiceContext
    let inbox: any InboxStorage
    let processedImports: any ProcessedImportStore
    let counters: any CounterStore

    public init(
        context: ServiceContext, inbox: any InboxStorage, processedImports: any ProcessedImportStore,
        counters: any CounterStore
    ) {
        self.context = context
        self.inbox = inbox
        self.processedImports = processedImports
        self.counters = counters
    }

    /// Removes everything the app stores about the household: every repository, the processed
    /// import ids, the counters, and the inbox folder with `failed/` (AC-16.2). The app then
    /// clears its own preferences and restarts onboarding. Safe to repeat after a failure.
    public func deleteAll() async throws {
        try await context.serialized {
            try await context.repositories.deleteAll()
            try await processedImports.deleteAll()
            try await counters.deleteAll()
            try await inbox.deleteAll()
        }
    }

    /// The instant before which records are pruned: `retentionMonths` calendar months before
    /// `now`, in the clock's time zone. A record exactly that old is kept.
    public func pruningCutoff() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = context.clock.timeZone
        let now = context.clock.now
        return calendar.date(byAdding: .month, value: -DataService.retentionMonths, to: now)
            ?? now.addingTimeInterval(-365 * 86_400)
    }

    /// Deletes cook logs, learning events and processed-import ids older than 12 months (NFR
    /// Storage). Facts stay (inferred, unconfirmed ones may fall back to observing on the next
    /// learning refresh once their events are gone): they are the household's current preferences. The app calls this at
    /// launch.
    ///
    /// - Returns: the cutoff used.
    @discardableResult
    public func prune() async throws -> Date {
        try await context.serialized {
            let cutoff = pruningCutoff()
            try await context.repositories.cookLogs.deleteCookLogs(before: cutoff)
            try await context.repositories.learningEvents.deleteEvents(before: cutoff)
            try await processedImports.deleteProcessed(before: cutoff)
            return cutoff
        }
    }
}
