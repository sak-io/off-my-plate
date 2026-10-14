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
}

/// An in-memory inbox (tests and previews).
public actor InMemoryInboxStorage: InboxStorage {
    private var files: [String: Data] = [:]
    private var failed: [String: Data] = [:]

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
    }

    public func remove(_ name: String) {
        files.removeValue(forKey: name)
    }

    public func deleteAll() {
        files.removeAll()
        failed.removeAll()
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
        guard manager.fileExists(atPath: url.path) else { throw InboxStorageError.notFound(name) }
        // Do not read a huge file just to reject it.
        if let size = (try manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue,
            size > InboxImport.maxFileBytes
        {
            throw InboxImportError.fileTooLarge(bytes: size)
        }
        return try Data(contentsOf: url)
    }

    public func quarantine(_ name: String) async throws {
        let url = try fileURL(name)
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { throw InboxStorageError.notFound(name) }
        let failedDirectory = root.appendingPathComponent(InboxFiles.failedDirectoryName, isDirectory: true)
        try manager.createDirectory(at: failedDirectory, withIntermediateDirectories: true)
        let destination = failedDirectory.appendingPathComponent(name)
        if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
        try manager.moveItem(at: url, to: destination)
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

    private func fileURL(_ name: String) throws -> URL {
        guard InboxFiles.importID(fromFileName: name) != nil else { throw InboxStorageError.invalidFileName(name) }
        return root.appendingPathComponent(name)
    }
}
