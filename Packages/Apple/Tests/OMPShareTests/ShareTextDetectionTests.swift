import Foundation
import Testing

@testable import OMPShare

@Suite("Share extension text detection")
struct ShareTextDetectionTests {
    @Test("plain text and its subtypes count as text", arguments: [
        "public.plain-text", "public.utf8-plain-text", "public.utf16-plain-text",
    ])
    func plainText(identifier: String) {
        #expect(ShareTextDetection.isText(typeIdentifier: identifier))
    }

    @Test("images, PDFs, links, files and unknown types are not text", arguments: [
        "public.png", "public.jpeg", "com.adobe.pdf", "public.url", "public.file-url", "public.data",
        "not.a.real.type.identifier", "",
    ])
    func notText(identifier: String) {
        #expect(!ShareTextDetection.isText(typeIdentifier: identifier))
    }

    @Test("a share is text when any attachment is plain text")
    func containsText() {
        #expect(ShareTextDetection.containsText(typeIdentifiers: ["public.url", "public.plain-text"]))
        #expect(!ShareTextDetection.containsText(typeIdentifiers: ["public.png", "com.adobe.pdf"]))
        #expect(!ShareTextDetection.containsText(typeIdentifiers: []))
        #expect(ShareTextDetection.firstTextIdentifier(in: ["public.png", "public.utf8-plain-text"]) == "public.utf8-plain-text")
    }

    @Test("loaded items: strings and UTF-8 data are read, web links and other objects are not")
    func loadedItems() throws {
        #expect(ShareTextLoader.string(from: "2 kg rice") == "2 kg rice")
        #expect(ShareTextLoader.string(from: Data("milk".utf8)) == "milk")
        #expect(ShareTextLoader.string(from: URL(string: "https://example.com/list")!) == nil)
        #expect(ShareTextLoader.string(from: 42) == nil)
        #expect(ShareTextLoader.string(from: nil) == nil)

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("eggs".utf8).write(to: file)
        #expect(ShareTextLoader.string(from: file) == "eggs")
    }
}
