import Foundation
import Testing

/// ADR 0011: the extension links only OMPDomain, OMPRecipes, OMPUI (and OMPShare, which itself
/// depends only on OMPDomain and OMPUI), never OMPServices, OMPData, OMPFeatures or OMPCapture,
/// so it cannot reach planning, approval, the household or the store. These tests read the
/// build files.
@Suite("Share extension link list")
struct ShareLinkListTests {
    private static let forbidden = ["OMPServices", "OMPData", "OMPFeatures", "OMPCapture", "OMPSafetyCheck"]

    private func repoFile(_ relative: String) throws -> String {
        // .../Packages/Apple/Tests/OMPShareTests/<this file> -> repository root.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return try String(contentsOf: url.appendingPathComponent(relative), encoding: .utf8)
    }

    /// The lines of the block that starts at the line containing `header` and ends at the next
    /// line with the same or smaller indentation that is not part of it.
    private func block(of text: String, startingWith header: String) throws -> [String] {
        let lines = text.components(separatedBy: "\n")
        let start = try #require(lines.firstIndex { $0.contains(header) })
        let indent = lines[start].prefix { $0 == " " }.count
        var result: [String] = []
        for line in lines[(start + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lineIndent = line.prefix { $0 == " " }.count
            if !trimmed.isEmpty && lineIndent <= indent { break }
            result.append(line)
        }
        return result
    }

    @Test("the extension target in project.yml excludes the services, data and feature modules")
    func projectYML() throws {
        let yml = try repoFile("App/project.yml")
        let lines = try block(of: yml, startingWith: "  OffMyPlateShare:")
        #expect(!lines.isEmpty)
        let dependencies = try block(of: lines.joined(separator: "\n"), startingWith: "    dependencies:").joined(separator: "\n")
        for name in Self.forbidden {
            #expect(!dependencies.contains(name), "The share extension must not link \(name)")
        }
        #expect(dependencies.contains("OMPShare"))
        #expect(dependencies.contains("OMPDomain"))
        #expect(dependencies.contains("OMPUI"))
    }

    @Test("the OMPShare package target depends only on OMPUI and OMPDomain")
    func packageTarget() throws {
        let manifest = try repoFile("Packages/Apple/Package.swift")
        let all = manifest.components(separatedBy: "\n")
        let start = try #require(all.firstIndex { $0 == "            name: \"OMPShare\"," })
        // Up to the closing "        )," of the .target(...) call.
        let end = try #require(all[start...].firstIndex { $0 == "        )," })
        let dependencies = all[start..<end].joined(separator: "\n")
        for name in Self.forbidden {
            #expect(!dependencies.contains(name), "OMPShare must not depend on \(name)")
        }
        #expect(dependencies.contains("OMPDomain"))
    }

    @Test("no OMPShare source imports a forbidden module")
    func sources() throws {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { directory.deleteLastPathComponent() }
        let sourceDirectory = directory.appendingPathComponent("Sources/OMPShare")
        let files = try FileManager.default.contentsOfDirectory(atPath: sourceDirectory.path)
        #expect(files.contains { $0.hasSuffix(".swift") })
        for file in files where file.hasSuffix(".swift") {
            let text = try String(contentsOf: sourceDirectory.appendingPathComponent(file), encoding: .utf8)
            for name in Self.forbidden {
                #expect(!text.contains("import \(name)"), "\(file) imports \(name)")
            }
        }
    }
}
