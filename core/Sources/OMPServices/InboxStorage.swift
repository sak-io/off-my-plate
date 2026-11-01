import Foundation
import OMPDomain

/// Why an inbox storage call failed.
public enum InboxStorageError: Error, Sendable, Hashable {
    /// The name is not an inbox file name (`InboxFiles.importID(fromFileName:)`).
    case invalidFileName(String)
    case notFound(String)
}

/// The Share Extension's inbox folder, as the import use case sees it (ADR 0011, T19).
///
/// File I/O sits behind this small protocol so tests use a temporary directory or the in-memory
/// fake. Names are file names inside the inbox folder, never paths; implementations reject
/// anything `InboxFiles` would not call an inbox file.
public protocol InboxStorage: Sendable {
    /// The names of the entries directly inside the inbox folder (any order; may include
    /// temporary files, which the caller filters with `InboxFiles`). Empty if the folder is missing.
    func fileNames() async throws -> [String]
    /// The contents of one inbox file.
    func read(_ name: String) async throws -> Data
    /// Moves a file to `failed/` (kept for the user, never dropped silently).
    func quarantine(_ name: String) async throws
    /// Deletes a file that was imported.
    func remove(_ name: String) async throws
    /// Deletes the inbox folder with everything in it, `failed/` included ("Delete all data").
    func deleteAll() async throws
    /// Keeps only the `keepNewest` most recently quarantined files in `failed/` and deletes the
    /// rest, so a hostile or buggy writer cannot grow it without bound (security audit L2).
    func pruneQuarantine(keepNewest: Int) async throws
}

extension InboxStorage {
    /// Default for storages without a `failed/` folder worth bounding.
    public func pruneQuarantine(keepNewest: Int) async throws {}
}

/// An in-memory inbox (tests and previews).
public actor InMemoryInboxStorage: InboxStorage {
    private var files: [String: Data] = [:]
    private var failed: [String: Data] = [:]
    /// Quarantine order, oldest first.
    private var failedOrder: [String] = []

    public init() {}

    /// Drops a file into the inbox, as the Share Extension would.
    public func put(_ name: String, _ data: Data) {
        files[name] = data
    }

    public func pendingNames() -> [String] {
        files.keys.sorted()
    }

    public func failedNames() -> [String] {
        failed.keys.sorted()
    }

    public func fileNames() -> [String] {
        Array(files.keys)
    }

    public func read(_ name: String) throws -> Data {
        guard InboxFiles.importID(fromFileName: name) != nil else { throw InboxStorageError.invalidFileName(name) }
        guard let data = files[name] else { throw InboxStorageError.notFound(name) }
        return data
    }

    public func quarantine(_ name: String) throws {
        guard InboxFiles.importID(fromFileName: name) != nil else { throw InboxStorageError.invalidFileName(name) }
        guard let data = files.removeValue(forKey: name) else { throw InboxStorageError.notFound(name) }
        failed[name] = data
        failedOrder.removeAll { $0 == name }
        failedOrder.append(name)
    }

    public func pruneQuarantine(keepNewest: Int) {
        let excess = failedOrder.count - max(keepNewest, 0)
        guard excess > 0 else { return }
        for name in failedOrder.prefix(excess) { failed.removeValue(forKey: name) }
        failedOrder.removeFirst(excess)
    }

    public func remove(_ name: String) {
        files.removeValue(forKey: name)
    }

    public func deleteAll() {
        files.removeAll()
        failed.removeAll()
        failedOrder.removeAll()
    }
}

/// The inbox as a real folder: `<root>/<importId>.json`, quarantine in `<root>/failed/`.
/// The app passes `<AppGroup>/Inbox`; tests pass a temporary directory.
public struct DirectoryInboxStorage: InboxStorage {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func fileNames() async throws -> [String] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: root.path) else { return [] }
        return try manager.contentsOfDirectory(atPath: root.path)
    }

    public func read(_ name: String) async throws -> Data {
        let url = try fileURL(name)
        let manager = FileManager.default
        // attributesOfItem does not follow a final symlink: a link (or anything that is not a
        // plain file) is reported as a bad file, so the caller quarantines it (security audit L3).
        guard let attributes = try? manager.attributesOfItem(atPath: url.path) else {
            throw InboxStorageError.notFound(name)
        }
        guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
            throw InboxImportError.invalid("The inbox entry is not a regular file.")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        // Read at most one byte more than the limit: the size check applies to the bytes
        // actually read, not to a size that may have changed since (and never reads a huge file).
        let data = try handle.read(upToCount: InboxImport.maxFileBytes + 1) ?? Data()
        if data.count > InboxImport.maxFileBytes { throw InboxImportError.fileTooLarge(bytes: data.count) }
        // The entry may have been swapped for a link between the check and the open (only code
        // in the app group can do that); re-check so such a read is not trusted.
        guard (try? manager.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeRegular else {
            throw InboxImportError.invalid("The inbox entry changed while it was read.")
        }
        return data
    }

    public func quarantine(_ name: String) async throws {
        let url = try fileURL(name)
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { throw InboxStorageError.notFound(name) }
        let failedDirectory = root.appendingPathComponent(InboxFiles.failedDirectoryName, isDirectory: true)
        try manager.createDirectory(
            at: failedDirectory, withIntermediateDirectories: true, attributes: Self.directoryAttributes)
        let destination = failedDirectory.appendingPathComponent(name)
        // fileExists follows links; a dangling link at the destination must be replaced too.
        if (try? manager.attributesOfItem(atPath: destination.path)) != nil {
            try manager.removeItem(at: destination)
        }
        try manager.moveItem(at: url, to: destination)
        // Order `failed/` by when a file was quarantined (a move keeps the old modification date).
        try? manager.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
    }

    public func pruneQuarantine(keepNewest: Int) async throws {
        let manager = FileManager.default
        let failedDirectory = root.appendingPathComponent(InboxFiles.failedDirectoryName, isDirectory: true)
        guard manager.fileExists(atPath: failedDirectory.path) else { return }
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let entries = try manager.contentsOfDirectory(
            at: failedDirectory, includingPropertiesForKeys: keys, options: [])
        let dated: [(url: URL, date: Date)] = entries.map {
            ($0, (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast)
        }
        // Newest first; ties broken by name so the result is deterministic.
        let sorted = dated.sorted {
            $0.date != $1.date ? $0.date > $1.date : $0.url.lastPathComponent < $1.url.lastPathComponent
        }
        for entry in sorted.dropFirst(max(keepNewest, 0)) { try? manager.removeItem(at: entry.url) }
    }

    public func remove(_ name: String) async throws {
        let url = try fileURL(name)
        let manager = FileManager.default
        if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
    }

    public func deleteAll() async throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: root.path) { try manager.removeItem(at: root) }
    }

    /// Data Protection Complete for the folders the app creates (ADR 0011): the app drains the
    /// inbox in the foreground, so an unlocked device is always the case. Other platforms ignore it.
    static var directoryAttributes: [FileAttributeKey: Any]? {
        #if os(iOS)
        [.protectionKey: FileProtectionType.complete]
        #else
        nil
        #endif
    }

    private func fileURL(_ name: String) throws -> URL {
        guard InboxFiles.importID(fromFileName: name) != nil else { throw InboxStorageError.invalidFileName(name) }
        return root.appendingPathComponent(name)
    }
}
