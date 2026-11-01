import Foundation
import Testing

@testable import OMPData

/// CloudKit-compatible modelling rules (ADR 0003, ADR 0015), checked on the source text so a
/// violation fails CI on macOS before any sync work starts:
/// 1. no `.unique` attribute and no `#Unique` anywhere in OMPData;
/// 2. every stored property of a schema record is optional or has a default value;
/// 3. every relationship property is optional.
/// Each check is also run on a planted violation, so the checker itself is proven to fail.
@Suite("CloudKit modelling rules")
struct CloudKitRulesTests {
    private static var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // OMPDataTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // Packages/Apple
            .appendingPathComponent("Sources/OMPData", isDirectory: true)
    }

    private static func swiftSources() throws -> [(name: String, text: String)] {
        let enumerator = try #require(FileManager.default.enumerator(at: sourcesDirectory, includingPropertiesForKeys: nil))
        var files: [(name: String, text: String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append((name: url.lastPathComponent, text: try String(contentsOf: url, encoding: .utf8)))
        }
        return files
    }

    /// Lines (outside `//` comments) that declare a unique constraint.
    static func uniqueViolations(in text: String) -> [String] {
        codeLines(text).filter { $0.contains(".unique") || $0.contains("#Unique") }
    }

    /// Stored `var` declarations inside the schema that are neither optional nor defaulted, and
    /// relationship properties that are not optional.
    static func optionalityViolations(in text: String) -> [String] {
        var violations: [String] = []
        var previousWasRelationship = false
        for line in codeLines(text) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            defer { previousWasRelationship = trimmed.hasPrefix("@Relationship") }
            guard trimmed.hasPrefix("var "), !trimmed.contains("{") else { continue }
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let typeAndDefault = trimmed[trimmed.index(after: colon)...]
            let type = typeAndDefault.split(separator: "=", maxSplits: 1).first.map(String.init) ?? ""
            let isOptional = type.trimmingCharacters(in: .whitespaces).hasSuffix("?")
            let hasDefault = typeAndDefault.contains("=")
            if previousWasRelationship ? !isOptional : !(isOptional || hasDefault) {
                violations.append(trimmed)
            }
        }
        return violations
    }

    private static func codeLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter {
            !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//")
        }
    }

    @Test("no unique constraint in any OMPData source file")
    func noUniqueConstraints() throws {
        let sources = try Self.swiftSources()
        #expect(sources.contains { $0.name == "SchemaV1.swift" })
        for source in sources {
            #expect(Self.uniqueViolations(in: source.text).isEmpty, "unique constraint in \(source.name)")
        }
    }

    @Test("every schema record property is optional or defaulted; relationships are optional")
    func everyPropertyOptionalOrDefaulted() throws {
        let schema = try #require(try Self.swiftSources().first { $0.name == "SchemaV1.swift" })
        #expect(Self.optionalityViolations(in: schema.text).isEmpty)
        // The schema really was scanned: it declares many stored properties.
        #expect(schema.text.components(separatedBy: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("var ") }.count > 100)
    }

    @Test("the checks fail on planted violations")
    func checksCatchPlantedViolations() {
        #expect(!Self.uniqueViolations(in: "    @Attribute(.unique) var id: String = \"\"").isEmpty)
        #expect(!Self.uniqueViolations(in: "    #Unique<Foo>([\\.id])").isEmpty)
        #expect(Self.uniqueViolations(in: "    // no .unique here").isEmpty)

        #expect(Self.optionalityViolations(in: "    var id: String") == ["var id: String"])
        #expect(Self.optionalityViolations(in: "    var id: String = \"\"\n    var name: String?").isEmpty)
        #expect(
            Self.optionalityViolations(in: "    @Relationship(deleteRule: .cascade)\n    var members: [MemberRecord] = []")
                == ["var members: [MemberRecord] = []"])
        #expect(
            Self.optionalityViolations(in: "    @Relationship(deleteRule: .cascade)\n    var members: [MemberRecord]? = []")
                .isEmpty)
    }
}
