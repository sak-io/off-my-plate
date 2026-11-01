import Foundation
import OMPDomain
import Testing

@testable import OMPShare

/// The App Group container is not available in CI simulators (CODE_SIGNING_ALLOWED=NO), so these
/// tests write into a temporary directory and never touch the real group.
@Suite("Share inbox writer")
struct ShareInboxWriterTests {
    private func sample(id: String = "abc-123") throws -> InboxImport {
        try InboxImport(
            importId: InboxImportID(id), createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            destination: .shoppingList, items: [InboxImport.Item(name: "Rice", quantity: 2, unit: .kilogram)])
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("omp-share-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(InboxFiles.directoryName, isDirectory: true)
    }

    @Test("writes <importId>.json that the app's reader accepts, creating the folder")
    func writesFile() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let item = try sample()
        try await DirectoryShareInboxWriter(root: root).write(item)

        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(InboxFiles.inboxFileNames(in: names) == ["abc-123.json"])
        let data = try Data(contentsOf: root.appendingPathComponent("abc-123.json"))
        #expect(try InboxImport.decode(data) == item)
    }

    @Test("recreates the inbox folder after Delete all data removed it")
    func recreatesFolder() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let writer = DirectoryShareInboxWriter(root: root)
        try await writer.write(sample(id: "first"))
        try FileManager.default.removeItem(at: root)
        try await writer.write(sample(id: "second"))
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(InboxFiles.inboxFileNames(in: names) == ["second.json"])
    }

    @Test("writing the same import again replaces the file")
    func idempotentRewrite() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let writer = DirectoryShareInboxWriter(root: root)
        try await writer.write(sample())
        try await writer.write(sample())
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(InboxFiles.inboxFileNames(in: names).count == 1)
    }

    @Test("a missing App Group gives no inbox folder")
    func noGroup() {
        #expect(ShareInbox.rootURL(appGroupID: "") == nil)
    }
}
