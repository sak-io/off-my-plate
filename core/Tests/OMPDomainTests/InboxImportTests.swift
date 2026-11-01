import Foundation
import OMPDomain
import Testing

private let createdAt = Date(timeIntervalSince1970: 1_791_763_200)  // 2026-10-12T00:00:00Z
private let importID: InboxImportID = "6f1c2a9e-3b7d-4c55-9a1e-0d2b8f4e7a10"

private func sampleImport() throws -> InboxImport {
    try InboxImport(
        importId: importID, createdAt: createdAt, destination: .shoppingList,
        items: [
            InboxImport.Item(name: "Rice", ingredientId: "rice", quantity: 2, unit: .kilogram),
            InboxImport.Item(name: "Milk", quantity: 2),
            InboxImport.Item(name: "Curry leaves"),
        ])
}

/// The decode error, or nil when decoding succeeded or threw something else.
private func decodeError(_ json: String) -> InboxImportError? {
    do {
        _ = try InboxImport.decode(Data(json.utf8))
        return nil
    } catch let error as InboxImportError {
        return error
    } catch {
        Issue.record("unexpected error type: \(error)")
        return nil
    }
}

private let goldenV1 = """
    {"createdAt":"2026-10-12T00:00:00Z","destination":"pantry","importId":"6f1c2a9e-3b7d-4c55-9a1e-0d2b8f4e7a10",\
    "items":[{"ingredientId":"tapioca","name":"Kappa","quantity":1,"unit":"kg"},{"name":"Kudampuli"}],\
    "schemaVersion":1}
    """

@Suite("InboxImport v1")
struct InboxImportTests {
    @Test("encode then decode gives the same import")
    func roundTrip() throws {
        let original = try sampleImport()
        let data = try original.encoded()
        #expect(try InboxImport.decode(data) == original)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"schemaVersion\":1"))
        #expect(json.contains("\"createdAt\":\"2026-10-12T00:00:00Z\""))
        #expect(json.contains("\"destination\":\"shoppingList\""))
        #expect(!json.contains("null"), "absent optionals are omitted")
    }

    @Test("the golden v1 file decodes to the documented fields")
    func goldenFile() throws {
        let decoded = try InboxImport.decode(Data(goldenV1.utf8))
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.importId == importID)
        #expect(decoded.createdAt == createdAt)
        #expect(decoded.destination == .pantry)
        #expect(
            decoded.items == [
                InboxImport.Item(name: "Kappa", ingredientId: "tapioca", quantity: 1, unit: .kilogram),
                InboxImport.Item(name: "Kudampuli"),
            ])
        #expect(decoded.fileName == "6f1c2a9e-3b7d-4c55-9a1e-0d2b8f4e7a10.json")
        #expect(String(decoding: try decoded.encoded(), as: UTF8.self) == goldenV1)
    }

    @Test("an unknown schemaVersion is rejected, whatever else the file contains", arguments: [0, 2, 99, -1])
    func unknownVersion(version: Int) {
        let json = goldenV1.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":\(version)")
        #expect(decodeError(json) == .unsupportedSchemaVersion(version))
        #expect(decodeError("{\"schemaVersion\":\(version),\"items\":\"v2 shape\"}") == .unsupportedSchemaVersion(version))
    }

    @Test("missing version, wrong types and non-JSON are malformed")
    func malformed() {
        for json in [
            "not json", "", "[]", "{\"importId\":\"a\"}", "{\"schemaVersion\":\"1\"}",
            goldenV1.replacingOccurrences(of: "\"pantry\"", with: "\"fridge\""),
            goldenV1.replacingOccurrences(of: "\"quantity\":1", with: "\"quantity\":-1"),
            goldenV1.replacingOccurrences(of: "\"kg\"", with: "\"bushel\""),
            goldenV1.replacingOccurrences(of: "2026-10-12T00:00:00Z", with: "yesterday"),
        ] {
            guard case .malformed = decodeError(json) else {
                Issue.record("expected malformed for \(json)")
                continue
            }
        }
    }

    @Test("rule violations are invalid: no items, empty name, bad id")
    func invalid() {
        let noItems = goldenV1.replacingOccurrences(
            of: #"[{"ingredientId":"tapioca","name":"Kappa","quantity":1,"unit":"kg"},{"name":"Kudampuli"}]"#, with: "[]")
        let emptyName = goldenV1.replacingOccurrences(of: "\"Kudampuli\"", with: "\"\"")
        let badID = goldenV1.replacingOccurrences(of: "6f1c2a9e-3b7d-4c55-9a1e-0d2b8f4e7a10", with: "../escape")
        for json in [noItems, emptyName, badID] {
            guard case .invalid = decodeError(json) else {
                Issue.record("expected invalid for \(json)")
                continue
            }
        }
        #expect(throws: InboxImportError.self) {
            try InboxImport(createdAt: createdAt, destination: .pantry, items: [])
        }
        #expect(throws: InboxImportError.self) {
            try InboxImport(importId: "UPPER", createdAt: createdAt, destination: .pantry, items: [.init(name: "a")])
        }
        let tooMany = Array(repeating: InboxImport.Item(name: "rice"), count: InboxImport.maxItems + 1)
        #expect(throws: InboxImportError.self) {
            try InboxImport(createdAt: createdAt, destination: .pantry, items: tooMany)
        }
    }

    @Test("files over the size cap are rejected before decoding")
    func tooLarge() {
        let data = Data(repeating: 0x20, count: InboxImport.maxFileBytes + 1)
        #expect(throws: InboxImportError.fileTooLarge(bytes: InboxImport.maxFileBytes + 1)) {
            try InboxImport.decode(data)
        }
    }

    @Test("items normalise their input")
    func itemNormalisation() {
        let long = String(repeating: "a", count: 300)
        #expect(InboxImport.Item(name: "  Rice \n").name == "Rice")
        #expect(InboxImport.Item(name: long).name.count == InboxImport.Item.maxNameLength)
        let negative = InboxImport.Item(name: "rice", quantity: -2, unit: .kilogram)
        #expect(negative.quantity == nil)
        #expect(negative.unit == .kilogram)
        #expect(InboxImport.Item(name: "rice", quantity: .infinity).quantity == nil)
        #expect(InboxImport.Item(name: "rice", quantity: .nan).quantity == nil)
        let pinch = InboxImport.Item(name: "hing", quantity: 1, unit: .pinch)
        #expect(pinch.quantity == nil && pinch.unit == nil)
    }

    @Test("a parsed Notes line becomes an item")
    func itemFromParsedLine() throws {
        let line = try #require(ShoppingTextParser.parse("- [ ] Kappa 1 kg").lines.first)
        #expect(
            InboxImport.Item(line, ingredientId: "tapioca")
                == InboxImport.Item(name: "Kappa", ingredientId: "tapioca", quantity: 1, unit: .kilogram))
    }

    @Test("createdAt is stored in whole seconds")
    func wholeSeconds() throws {
        let value = try InboxImport(
            createdAt: Date(timeIntervalSince1970: 1_791_763_200.75), destination: .pantry, items: [.init(name: "a")])
        #expect(value.createdAt == createdAt)
        #expect(try InboxImport.decode(value.encoded()) == value)
    }

    @Test("new imports get a fresh, valid, lowercased UUID id")
    func generatedID() throws {
        let first = try InboxImport(createdAt: createdAt, destination: .shoppingList, items: [.init(name: "a")])
        let second = try InboxImport(createdAt: createdAt, destination: .shoppingList, items: [.init(name: "a")])
        #expect(first.importId != second.importId)
        #expect(InboxFiles.isValidID(first.importId.rawValue))
        #expect(InboxFiles.importID(fromFileName: first.fileName) == first.importId)
    }
}

@Suite("Inbox file naming and share input")
struct InboxFilesTests {
    @Test("file names are <importId>.json and parse back")
    func naming() {
        #expect(InboxFiles.fileName(for: importID) == "6f1c2a9e-3b7d-4c55-9a1e-0d2b8f4e7a10.json")
        #expect(InboxFiles.importID(fromFileName: "6f1c2a9e-3b7d-4c55-9a1e-0d2b8f4e7a10.json") == importID)
        #expect(InboxFiles.directoryName == "Inbox")
        #expect(InboxFiles.failedDirectoryName == "failed")
    }

    @Test(
        "temporary, hidden, foreign and path-escaping names are ignored",
        arguments: [
            "", ".json", ".abc.json", "abc.json.tmp", "abc.JSON", "ABC.json", "../abc.json", "a/b.json", "-abc.json",
            "abc def.json", "failed", String(repeating: "a", count: 65) + ".json", "ab\u{0}c.json", "kappa.json ",
        ])
    func ignoredNames(name: String) {
        #expect(InboxFiles.importID(fromFileName: name) == nil)
    }

    @Test("a directory listing is filtered and sorted")
    func listing() {
        let names = ["b.json", ".tmp-1", "failed", "a.json", "c.json.tmp", "a-1.json"]
        #expect(InboxFiles.inboxFileNames(in: names) == ["a-1.json", "a.json", "b.json"])
    }

    @Test("AC-11.4: only plain text is accepted from the share sheet")
    func shareInput() {
        for type in ["public.plain-text", "public.utf8-plain-text", "public.text"] {
            #expect(ShareInputPolicy.isSupported(typeIdentifier: type))
        }
        for type in ["public.image", "public.jpeg", "com.adobe.pdf", "public.url", "public.file-url", "public.html"] {
            #expect(!ShareInputPolicy.isSupported(typeIdentifier: type))
        }
        #expect(ShareInputPolicy.preferredTypeIdentifier(among: ["public.jpeg", "public.plain-text"]) == "public.plain-text")
        #expect(ShareInputPolicy.preferredTypeIdentifier(among: ["public.url", "com.adobe.pdf"]) == nil)
    }

    @Test("an absurd or non-finite quantity is dropped by the initialiser and rejected when decoding (audit L1)")
    func absurdQuantity() throws {
        #expect(InboxImport.Item(name: "Rice", quantity: 1e308, unit: .kilogram).quantity == nil)
        #expect(InboxImport.Item(name: "Rice", quantity: .infinity, unit: .kilogram).quantity == nil)
        #expect(InboxImport.Item(name: "Rice", quantity: .nan, unit: .kilogram).quantity == nil)
        #expect(
            InboxImport.Item(name: "Rice", quantity: InboxImport.Item.maxQuantity, unit: .kilogram).quantity
                == InboxImport.Item.maxQuantity)
        let huge = goldenV1.replacingOccurrences(of: "\"quantity\":1,", with: "\"quantity\":1e308,")
        #expect(huge != goldenV1)
        #expect(decodeError(huge) != nil)
    }
}
