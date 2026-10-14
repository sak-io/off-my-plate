import Foundation
import OMPDomain

/// Hands a confirmed import to the app (ADR 0011).
public protocol ShareInboxWriting: Sendable {
    func write(_ item: InboxImport) async throws
}

/// Where the inbox folder is: `<AppGroup>/Inbox` (names fixed by `InboxFiles`).
public enum ShareInbox {
    /// The inbox folder for the App Group, or nil when the group is not available (for example an
    /// unsigned simulator build). Does not create the folder: the writer does, on every write,
    /// because "Delete all data" removes it.
    public static func rootURL(appGroupID: String, fileManager: FileManager = .default) -> URL? {
        guard !appGroupID.isEmpty,
            let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else { return nil }
        return container.appendingPathComponent(InboxFiles.directoryName, isDirectory: true)
    }
}

/// Writes `<root>/<importId>.json` atomically with Data Protection Complete. The folder is
/// (re)created on every write (T19 review: "Delete all data" removes it).
public struct DirectoryShareInboxWriter: ShareInboxWriting {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func write(_ item: InboxImport) async throws {
        let data = try item.encoded()
        let manager = FileManager.default
        var attributes: [FileAttributeKey: Any] = [:]
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.complete
        options.insert(.completeFileProtection)
        #endif
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: attributes)
        try data.write(to: root.appendingPathComponent(item.fileName, isDirectory: false), options: options)
    }
}
