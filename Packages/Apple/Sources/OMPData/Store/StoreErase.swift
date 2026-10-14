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
    /// A busy store (another connection mid-write) throws; the records are already deleted and
    /// the caller may simply try again.
    static func purge(storeAt url: URL) throws {
        #if canImport(SQLite3)
        var handle: OpaquePointer?
        let opened = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil)
        defer { sqlite3_close(handle) }
        guard opened == SQLITE_OK else { throw Failure(code: opened) }
        sqlite3_busy_timeout(handle, 5_000)
        for statement in ["PRAGMA secure_delete = ON;", "VACUUM;", "PRAGMA wal_checkpoint(TRUNCATE);"] {
            let result = sqlite3_exec(handle, statement, nil, nil, nil)
            guard result == SQLITE_OK else { throw Failure(code: result) }
        }
        #endif
    }
}
