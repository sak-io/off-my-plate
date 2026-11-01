import Foundation
import UniformTypeIdentifiers

/// Decides whether shared content is text we can read (F10, AC-11.4). Works on type identifier
/// strings, so tests do not need real `NSItemProvider`s or the App Group.
///
/// Only plain text counts (`public.plain-text` and its subtypes such as `public.utf8-plain-text`).
/// Images, PDFs, files and links are "not text": links are never followed.
public enum ShareTextDetection {
    /// True when `typeIdentifier` is plain text or a subtype of it.
    public static func isText(typeIdentifier: String) -> Bool {
        guard let type = UTType(typeIdentifier) else { return false }
        return type.conforms(to: .plainText)
    }

    /// True when any of the identifiers is plain text.
    public static func containsText(typeIdentifiers: [String]) -> Bool {
        typeIdentifiers.contains { isText(typeIdentifier: $0) }
    }

    /// The first identifier that is plain text, or nil.
    public static func firstTextIdentifier(in typeIdentifiers: [String]) -> String? {
        typeIdentifiers.first { isText(typeIdentifier: $0) }
    }
}
