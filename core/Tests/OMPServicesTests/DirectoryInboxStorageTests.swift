import Foundation
import OMPDomain
import OMPServices
import Testing

/// An inbox whose reads fail with a storage error (a transient I/O problem).
private struct FailingReadInbox: InboxStorage {
    struct Failure: Error {}
    let names: [String]

    func fileNames() async throws -> [String] { names }
    func read(_ name: String) async throws -> Data { throw Failure() }
    func quarantine(_ name: String) async throws { Issue.record("must not quarantine \(name)") }
    func remove(_ name: String) async throws {}
    func deleteAll() async throws {}
}

@Suite("DirectoryInboxStorage on a real temporary folder (ADR 0011, AC-16.2, T19)")
struct DirectoryInboxStorageTests {
    /// A fresh root that does not exist yet; removed afterwards by `cleanup`.
    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("omp-inbox-" + UUID().uuidString.lowercased())
    }

    private func write(_ data: Data, _ name: String, in root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: root.appendingPathComponent(name))
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func cleanup(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    @Test("fileNames is empty when the folder does not exist, and lists entries once it does")
    func missingRoot() async throws {
        let root = makeRoot()
        defer { cleanup(root) }
        let storage = DirectoryInboxStorage(root: root)
        #expect(try await storage.fileNames().isEmpty)
        try write(Data("{}".utf8), "import-1.json", in: root)
        #expect(try await storage.fileNames() == ["import-1.json"])
        #expect(try await storage.read("import-1.json") == Data("{}".utf8))
    }

    @Test("quarantine moves the file into failed/ and replaces an older file of the same name")
    func quarantineMovesAndOverwrites() async throws {
        let root = makeRoot()
        defer { cleanup(root) }
        let storage = DirectoryInboxStorage(root: root)
        let failed = root.appendingPathComponent("failed", isDirectory: true)

        try write(Data("old".utf8), "import-1.json", in: root)
        try await storage.quarantine("import-1.json")
        #expect(!exists(root.appendingPathComponent("import-1.json")))
        #expect(try Data(contentsOf: failed.appendingPathComponent("import-1.json")) == Data("old".utf8))

        try write(Data("new".utf8), "import-1.json", in: root)
        try await storage.quarantine("import-1.json")
        #expect(!exists(root.appendingPathComponent("import-1.json")))
        #expect(try Data(contentsOf: failed.appendingPathComponent("import-1.json")) == Data("new".utf8))
        // The quarantined file is no longer an inbox entry.
        #expect(InboxFiles.inboxFileNames(in: try await storage.fileNames()).isEmpty)

        do {
            try await storage.quarantine("import-gone.json")
            Issue.record("expected notFound")
        } catch let error as InboxStorageError {
            #expect(error == .notFound("import-gone.json"))
        }
    }

    @Test("remove deletes a file and is harmless for a missing one")
    func removeFile() async throws {
        let root = makeRoot()
        defer { cleanup(root) }
        let storage = DirectoryInboxStorage(root: root)
        try write(Data("x".utf8), "import-1.json", in: root)
        try await storage.remove("import-1.json")
        #expect(!exists(root.appendingPathComponent("import-1.json")))
        try await storage.remove("import-1.json")
    }

    @Test("a file over 256 KiB is rejected as too large")
    func oversizeRejected() async throws {
        let root = makeRoot()
        defer { cleanup(root) }
        let storage = DirectoryInboxStorage(root: root)
        let size = InboxImport.maxFileBytes + 1
        try write(Data(repeating: 0x20, count: size), "import-big.json", in: root)
        do {
            _ = try await storage.read("import-big.json")
            Issue.record("expected fileTooLarge")
        } catch let error as InboxImportError {
            #expect(error == .fileTooLarge(bytes: size))
        }
        // Exactly at the limit is readable.
        try write(Data(repeating: 0x20, count: InboxImport.maxFileBytes), "import-max.json", in: root)
        #expect(try await storage.read("import-max.json").count == InboxImport.maxFileBytes)
    }

    @Test("names that are not inbox files are rejected by every call (no path escape)")
    func badNamesRejected() async throws {
        let root = makeRoot()
        defer { cleanup(root) }
        let storage = DirectoryInboxStorage(root: root)
        let outside = root.deletingLastPathComponent().appendingPathComponent("x.json")
        for name in ["../x.json", "a/b.json", "/etc/passwd.json", "import-1.txt", ".hidden.json", "failed", ""] {
            for call in 0..<3 {
                do {
                    switch call {
                    case 0: _ = try await storage.read(name)
                    case 1: try await storage.quarantine(name)
                    default: try await storage.remove(name)
                    }
                    Issue.record("expected invalidFileName for \(name)")
                } catch let error as InboxStorageError {
                    #expect(error == .invalidFileName(name))
                }
            }
        }
        #expect(!exists(outside))
    }

    @Test("deleteAll removes the folder with failed/ inside, and is harmless when it is already gone")
    func deleteAllRemovesRoot() async throws {
        let root = makeRoot()
        defer { cleanup(root) }
        let storage = DirectoryInboxStorage(root: root)
        try write(Data("a".utf8), "import-1.json", in: root)
        try write(Data("b".utf8), "import-2.json", in: root)
        try await storage.quarantine("import-2.json")
        #expect(exists(root.appendingPathComponent("failed")))

        try await storage.deleteAll()
        #expect(!exists(root))
        #expect(try await storage.fileNames().isEmpty)
        try await storage.deleteAll()
    }

    @Test("drain with a real folder: a garbage file lands in failed/, a good one is merged and deleted")
    func drainThroughDirectory() async throws {
        let root = makeRoot()
        defer { cleanup(root) }
        let storage = DirectoryInboxStorage(root: root)
        let env = ServicesBEnv()
        let imports = ImportService(context: env.base.context, inbox: storage, processedImports: env.processed)
        let good = try ServicesBFixture.inboxFile(id: "import-good", items: [InboxImport.Item(name: "Rice")])
        try write(good.data, good.name, in: root)
        try write(Data("garbage".utf8), "import-bad.json", in: root)

        let summary = try await imports.drainInbox()
        #expect(summary.filesImported == 1)
        #expect(summary.quarantined == ["import-bad.json"])
        #expect(!exists(root.appendingPathComponent("import-good.json")))
        #expect(!exists(root.appendingPathComponent("import-bad.json")))
        #expect(exists(root.appendingPathComponent("failed").appendingPathComponent("import-bad.json")))
        #expect(try await env.repositories.shopping.fetchAll().count == 1)
    }

    @Test("a storage error leaves the file in the inbox as stuck instead of quarantining it")
    func storageErrorIsNotQuarantine() async throws {
        let env = ServicesBEnv()
        let imports = ImportService(
            context: env.base.context, inbox: FailingReadInbox(names: ["import-1.json"]),
            processedImports: env.processed)
        let summary = try await imports.drainInbox()
        #expect(summary.stuck == ["import-1.json"])
        #expect(summary.quarantined.isEmpty)
        #expect(summary.filesImported == 0)
        #expect(try await env.processed.count() == 0)
    }

    @Test("a symlink in the inbox is not followed: reading it fails as a bad file and drain quarantines the link (audit L3)")
    func symlinkIsNotFollowed() async throws {
        let root = makeRoot()
        defer { cleanup(root) }
        let outside = makeRoot()
        defer { cleanup(outside) }
        let storage = DirectoryInboxStorage(root: root)
        let env = ServicesBEnv()
        let secret = try ServicesBFixture.inboxFile(id: "import-secret", items: [InboxImport.Item(name: "Secret")])
        try write(secret.data, "outside.json", in: outside)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("import-link.json")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: outside.appendingPathComponent("outside.json"))

        do {
            _ = try await storage.read("import-link.json")
            Issue.record("expected the symlink to be rejected")
        } catch is InboxImportError {
        }

        let imports = ImportService(context: env.base.context, inbox: storage, processedImports: env.processed)
        let summary = try await imports.drainInbox()
        #expect(summary.quarantined == ["import-link.json"])
        #expect(summary.filesImported == 0)
        #expect(try await env.repositories.shopping.fetchAll().isEmpty)
        // The target outside the inbox is untouched.
        #expect(exists(outside.appendingPathComponent("outside.json")))
    }

    @Test("a directory named like an inbox file is rejected, not read")
    func directoryIsNotAFile() async throws {
        let root = makeRoot()
        defer { cleanup(root) }
        let storage = DirectoryInboxStorage(root: root)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("import-dir.json"), withIntermediateDirectories: true)
        do {
            _ = try await storage.read("import-dir.json")
            Issue.record("expected rejection")
        } catch is InboxImportError {
        }
    }

    @Test("pruneQuarantine keeps the newest files in failed/ and deletes the rest (audit L2)")
    func pruneKeepsNewest() async throws {
        let root = makeRoot()
        defer { cleanup(root) }
        let storage = DirectoryInboxStorage(root: root)
        let failed = root.appendingPathComponent("failed", isDirectory: true)
        try FileManager.default.createDirectory(at: failed, withIntermediateDirectories: true)
        for number in 0..<5 {
            let url = failed.appendingPathComponent("import-\(number).json")
            try Data("x".utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(number) * 60)],
                ofItemAtPath: url.path)
        }
        try await storage.pruneQuarantine(keepNewest: 2)
        let left = try FileManager.default.contentsOfDirectory(atPath: failed.path).sorted()
        #expect(left == ["import-3.json", "import-4.json"])
        // Harmless when failed/ does not exist.
        try await DirectoryInboxStorage(root: makeRoot()).pruneQuarantine(keepNewest: 2)
    }
}
