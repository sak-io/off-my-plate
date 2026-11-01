import Foundation

#if canImport(SQLite3)
import SQLite3
#endif

extension PersistenceStore {
    /// "Delete all data" at store level (AC-16.2, T20 review-1): removes every record, then
    /// rewrites the SQLite file with `secure_delete` on and truncates the write-ahead log, so
    /// deleted rows do not linger in free pages or in `-wal`. The container and the
    /// repositories built from it stay usable (onboarding starts over on the same store).
    ///
    /// Inbox files, counters kept outside the store and preferences are the caller's part.
    public func eraseAllData() async throws {
        try await deleteAllData()
        guard case .directory(let directory) = location else { return }
        try StoreCompaction.purge(storeAt: PersistenceStore.storeURL(in: directory))
    }
}

/// Rewrites a SQLite store so deleted content is gone from disk.
enum StoreCompaction {
    struct Failure: Error, Equatable {
        let code: Int32
    }

    /// `PRAGMA secure_delete`, `VACUUM`, then `wal_checkpoint(TRUNCATE)` on a second connection.
    /// A blocked checkpoint is not an error code: SQLite reports it in the result row (`busy`),
    /// so that row is read and the checkpoint retried a few times before throwing. A busy store
    /// throws; the records are already deleted and the caller may try again.
    static func purge(storeAt url: URL, attempts: Int = 5) throws {
        #if canImport(SQLite3)
        var handle: OpaquePointer?
        let opened = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil)
        defer { sqlite3_close(handle) }
        guard opened == SQLITE_OK else { throw Failure(code: opened) }
        sqlite3_busy_timeout(handle, 5_000)
        for statement in ["PRAGMA secure_delete = ON;", "VACUUM;"] {
            let result = sqlite3_exec(handle, statement, nil, nil, nil)
            guard result == SQLITE_OK else { throw Failure(code: result) }
        }
        for attempt in 0..<max(1, attempts) {
            if try checkpointTruncated(handle) { return }
            if attempt < attempts - 1 { Thread.sleep(forTimeInterval: 0.2) }
        }
        throw Failure(code: SQLITE_BUSY)
        #endif
    }

    #if canImport(SQLite3)
    /// Runs `wal_checkpoint(TRUNCATE)` and returns whether it was not blocked (`busy == 0`).
    private static func checkpointTruncated(_ handle: OpaquePointer?) throws -> Bool {
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(handle, "PRAGMA wal_checkpoint(TRUNCATE);", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        guard prepared == SQLITE_OK else { throw Failure(code: prepared) }
        let stepped = sqlite3_step(statement)
        guard stepped == SQLITE_ROW else {
            // A database without a write-ahead log returns no row at all.
            if stepped == SQLITE_DONE { return true }
            throw Failure(code: stepped)
        }
        return sqlite3_column_int(statement, 0) == 0
    }
    #endif
}
