import Foundation

public typealias InboxImportID = EntityID<InboxImport>

/// Why an inbox file was rejected. The app moves such files to `Inbox/failed/` and tells the
/// user (ADR 0011); it never drops them silently.
public enum InboxImportError: Error, Sendable, Hashable {
    /// The file declares a `schemaVersion` this build does not read.
    case unsupportedSchemaVersion(Int)
    /// The file is larger than `InboxImport.maxFileBytes`.
    case fileTooLarge(bytes: Int)
    /// Not JSON, or a field is missing or of the wrong type.
    case malformed(String)
    /// Well-formed JSON that breaks a rule of the format (empty items, bad id, ...).
    case invalid(String)
}

/// One confirmed Notes import, written by the Share Extension to `<AppGroup>/Inbox/<importId>.json`
/// and drained by the app (ADR 0011, AC-11.3). Format `InboxImport v1`:
///
/// ```json
/// {"createdAt":"2026-10-13T08:30:00Z","destination":"shoppingList","importId":"<lowercased uuid>",
///  "items":[{"ingredientId":"rice","name":"Rice","quantity":2,"unit":"kg"},{"name":"Curry leaves"}],
///  "schemaVersion":1}
/// ```
///
/// Text only (AC-11.4): items carry names and amounts, never images or links. Every initialiser,
/// including decoding, enforces the rules below, so an invalid import cannot be written or read.
public struct InboxImport: Sendable, Hashable, Codable {
    /// Where the user chose to add the items (S-40).
    public enum Destination: String, Sendable, Hashable, Codable, CaseIterable {
        case shoppingList
        case pantry
    }

    /// One confirmed row.
    public struct Item: Sendable, Hashable, Codable {
        public static let maxNameLength = 200
        /// Largest amount one imported row may carry (security audit L1); a larger one is dropped
        /// like a non-finite one, and a file that says otherwise fails to decode.
        public static let maxQuantity: Double = 100_000

        /// As shown on the review screen (possibly edited by the user).
        public let name: String
        /// Set when the review row was matched to the taxonomy; otherwise the app resolves or keeps
        /// the item as free text.
        public let ingredientId: IngredientID?
        public let quantity: Double?
        public let unit: MeasureUnit?

        /// Normalises its input: the name is trimmed and cut to `maxNameLength` characters; a
        /// quantity that is not finite, positive and at most `maxQuantity` is dropped, and so is a non-quantified unit
        /// ("pinch") together with its amount.
        public init(
            name: String, ingredientId: IngredientID? = nil, quantity: Double? = nil, unit: MeasureUnit? = nil
        ) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            self.name = String(trimmed.prefix(Item.maxNameLength))
            self.ingredientId = ingredientId
            let quantified = unit.map(\.isQuantified) ?? true
            if let quantity, quantity.isFinite, quantity > 0, quantity <= Item.maxQuantity, quantified {
                self.quantity = quantity
                self.unit = unit
            } else {
                self.quantity = nil
                self.unit = quantified ? unit : nil
            }
        }

        /// A row from the Notes parser, optionally matched to an ingredient.
        public init(_ line: ParsedShoppingLine, ingredientId: IngredientID? = nil) {
            self.init(name: line.name, ingredientId: ingredientId, quantity: line.qty, unit: line.unit)
        }

        private enum CodingKeys: String, CodingKey {
            case name, ingredientId, quantity, unit
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let name = try container.decode(String.self, forKey: .name)
            let quantity = try container.decodeIfPresent(Double.self, forKey: .quantity)
            let unit = try container.decodeIfPresent(MeasureUnit.self, forKey: .unit)
            self.init(
                name: name, ingredientId: try container.decodeIfPresent(IngredientID.self, forKey: .ingredientId),
                quantity: quantity, unit: unit)
            guard self.name == name else {
                throw DecodingError.dataCorruptedError(
                    forKey: .name, in: container,
                    debugDescription: "A name must be trimmed and at most \(Item.maxNameLength) characters.")
            }
            guard self.quantity == quantity, self.unit == unit else {
                throw DecodingError.dataCorruptedError(
                    forKey: .quantity, in: container,
                    debugDescription: "A quantity must be finite, positive and at most 100000, with a quantified unit.")
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(ingredientId, forKey: .ingredientId)
            try container.encodeIfPresent(quantity, forKey: .quantity)
            try container.encodeIfPresent(unit, forKey: .unit)
        }
    }

    /// The only version this build writes and reads.
    public static let currentSchemaVersion = 1
    /// Same cap as the parser's line cap (plan section 11).
    public static let maxItems = ShoppingTextParser.maxLines
    /// Larger files are rejected before decoding.
    public static let maxFileBytes = 256 * 1024

    public let schemaVersion: Int
    public let importId: InboxImportID
    /// Whole seconds (the file stores ISO 8601 without fractions).
    public let createdAt: Date
    public let destination: Destination
    public let items: [Item]

    /// A new v1 import. Throws `InboxImportError.invalid` when `items` is empty or too long, an
    /// item has an empty name, or `importId` is not a valid file stem (`InboxFiles.isValidID`).
    public init(
        importId: InboxImportID = .generate(), createdAt: Date, destination: Destination, items: [Item]
    ) throws {
        try self.init(
            schemaVersion: InboxImport.currentSchemaVersion, importId: importId, createdAt: createdAt,
            destination: destination, items: items)
    }

    private init(schemaVersion: Int, importId: InboxImportID, createdAt: Date, destination: Destination, items: [Item])
        throws
    {
        guard schemaVersion == InboxImport.currentSchemaVersion else {
            throw InboxImportError.unsupportedSchemaVersion(schemaVersion)
        }
        guard InboxFiles.isValidID(importId.rawValue) else {
            throw InboxImportError.invalid("importId must be 1-64 characters of a-z, 0-9 and '-'.")
        }
        guard !items.isEmpty else { throw InboxImportError.invalid("An import needs at least one item.") }
        guard items.count <= InboxImport.maxItems else {
            throw InboxImportError.invalid("An import has at most \(InboxImport.maxItems) items.")
        }
        guard items.allSatisfy({ !$0.name.isEmpty }) else {
            throw InboxImportError.invalid("Every item needs a name.")
        }
        let seconds = createdAt.timeIntervalSince1970
        guard seconds.isFinite else { throw InboxImportError.invalid("createdAt must be a real date.") }
        self.schemaVersion = schemaVersion
        self.importId = importId
        self.createdAt = Date(timeIntervalSince1970: seconds.rounded(.down))
        self.destination = destination
        self.items = items
    }

    /// The file name in the inbox directory: `<importId>.json`.
    public var fileName: String { InboxFiles.fileName(for: importId) }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, importId, createdAt, destination, items
    }

    /// Reads `schemaVersion` first, so a file from another version fails as
    /// `unsupportedSchemaVersion` whatever else it contains.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == InboxImport.currentSchemaVersion else {
            throw InboxImportError.unsupportedSchemaVersion(version)
        }
        try self.init(
            schemaVersion: version,
            importId: try container.decode(InboxImportID.self, forKey: .importId),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            destination: try container.decode(Destination.self, forKey: .destination),
            items: try container.decode([Item].self, forKey: .items))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(importId, forKey: .importId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(destination, forKey: .destination)
        try container.encode(items, forKey: .items)
    }

    // MARK: - File contents

    /// The file contents: UTF-8 JSON with sorted keys and an ISO 8601 `createdAt`.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Reads a file written by `encoded()`. Throws only `InboxImportError`.
    public static func decode(_ data: Data) throws -> InboxImport {
        guard data.count <= maxFileBytes else { throw InboxImportError.fileTooLarge(bytes: data.count) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(InboxImport.self, from: data)
        } catch let error as InboxImportError {
            throw error
        } catch {
            throw InboxImportError.malformed(String(describing: error))
        }
    }
}
