/// Names inside the App Group inbox (ADR 0011). Paths are built by the app layer; Core only
/// fixes the names, so the extension and the app cannot disagree.
///
/// Layout: `<AppGroup>/Inbox/<importId>.json`, quarantine in `<AppGroup>/Inbox/failed/`.
public enum InboxFiles {
    public static let directoryName = "Inbox"
    public static let failedDirectoryName = "failed"
    public static let fileExtension = "json"
    /// Longest accepted id (a lowercased UUID is 36 characters).
    public static let maxIDLength = 64

    /// `<importId>.json`. The id is validated by `InboxImport`, so callers never build a path from
    /// an unchecked string.
    public static func fileName(for id: InboxImportID) -> String {
        id.rawValue + "." + fileExtension
    }

    /// The import id in a directory entry, or nil for anything that is not an inbox file: hidden
    /// or temporary files (an atomic write in progress), other extensions, and names that could
    /// escape the directory ("../x.json") or are not a plain id.
    public static func importID(fromFileName name: String) -> InboxImportID? {
        let suffix = "." + fileExtension
        guard name.hasSuffix(suffix) else { return nil }
        let stem = String(name.dropLast(suffix.count))
        guard isValidID(stem) else { return nil }
        return InboxImportID(stem)
    }

    /// The inbox file names among `names` (a directory listing), sorted by name so the drain order
    /// is deterministic. Names do not encode time; the app may re-sort by `createdAt`.
    public static func inboxFileNames(in names: [String]) -> [String] {
        names.filter { importID(fromFileName: $0) != nil }.sorted()
    }

    /// 1 to `maxIDLength` characters, each `a`-`z`, `0`-`9` or `-`, not starting with `-`.
    public static func isValidID(_ id: String) -> Bool {
        guard !id.isEmpty, id.utf8.count <= maxIDLength, id.first != "-" else { return false }
        return id.utf8.allSatisfy { byte in
            (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x30 && byte <= 0x39) || byte == 0x2D
        }
    }
}

/// What the Share Extension accepts (AC-11.4): plain text only. Images, PDFs, links and anything
/// else get "I can only read text for now." (C-171). Identifiers are Uniform Type Identifier
/// strings, so Core needs no Apple framework.
public enum ShareInputPolicy {
    /// Plain-text types a shared note arrives as.
    public static let supportedTypeIdentifiers: Set<String> = [
        "public.plain-text", "public.utf8-plain-text", "public.utf16-plain-text", "public.text",
    ]

    public static func isSupported(typeIdentifier: String) -> Bool {
        supportedTypeIdentifiers.contains(typeIdentifier)
    }

    /// The first supported identifier among those offered by a shared item, or nil when the item
    /// is not text.
    public static func preferredTypeIdentifier(among offered: [String]) -> String? {
        offered.first { isSupported(typeIdentifier: $0) }
    }
}
