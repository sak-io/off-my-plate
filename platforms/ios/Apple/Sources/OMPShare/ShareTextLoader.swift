import Foundation
import OMPDomain

/// Reads the shared text out of the extension's input items (F10). Text only: file URLs are read
/// up to the parser's byte cap, web links are ignored (AC-11.4).
public enum ShareTextLoader {
    /// Every type identifier the providers offer.
    public static func typeIdentifiers(of providers: [NSItemProvider]) -> [String] {
        providers.flatMap { $0.registeredTypeIdentifiers }
    }

    /// The first non-empty text offered by `providers`, or nil when there is none.
    @MainActor
    public static func text(from providers: [NSItemProvider]) async -> String? {
        for provider in providers {
            guard let identifier = ShareTextDetection.firstTextIdentifier(in: provider.registeredTypeIdentifiers)
            else { continue }
            let loaded: String? = await withCheckedContinuation { continuation in
                // `@Sendable` keeps the handler off the main actor: the system calls it on a background queue.
                provider.loadItem(forTypeIdentifier: identifier, options: nil) { @Sendable item, _ in
                    continuation.resume(returning: ShareTextLoader.string(from: item))
                }
            }
            if let loaded, !loaded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return loaded }
        }
        return nil
    }

    /// The text in what `loadItem` returned: a string, UTF-8 data, or a local text file. At most
    /// `ShoppingTextParser.maxInputBytes + 1` bytes are read, so the parser still sees that the
    /// text was cut.
    static func string(from item: Any?) -> String? {
        let limit = ShoppingTextParser.maxInputBytes + 1
        switch item {
        case let text as String:
            return text
        case let data as Data:
            return String(decoding: data.prefix(limit), as: UTF8.self)
        case let url as URL:
            guard url.isFileURL, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: limit) else { return nil }
            return String(decoding: data, as: UTF8.self)
        default:
            return nil
        }
    }
}
