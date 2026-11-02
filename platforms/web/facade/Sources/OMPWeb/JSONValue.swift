import Foundation

/// A parsed JSON document. The facade uses it for request arguments (decoded per operation into
/// typed structs) and to normalise output (sorted keys, sets in a fixed order).
///
/// Integers stay integers (`Int64`, because `Int` is 32 bit on wasm32); other numbers are `Double`.
enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let dictionary) = self { return dictionary[key] }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// The value at a dotted path ("result.plan.id", "result.plan.meals.0.id"); numeric segments index arrays.
    func value(atPath path: String) -> JSONValue? {
        var current: JSONValue = self
        for segment in path.split(separator: ".").map(String.init) {
            switch current {
            case .object(let dictionary):
                guard let next = dictionary[segment] else { return nil }
                current = next
            case .array(let items):
                guard let index = Int(segment), index >= 0, index < items.count else { return nil }
                current = items[index]
            default:
                return nil
            }
        }
        return current
    }
}

/// Stable JSON output: sorted keys, no whitespace, no escaped slashes, ISO-8601 dates, and every set
/// (which Swift encodes in a per-process random order) sorted.
enum CanonicalJSON {
    /// Object keys whose arrays are encoded from a Swift `Set` of strings.
    static let setKeys: Set<String> = [
        "excludedTags", "schoolDays", "tags", "mayContain", "mealTypes", "declaredTags", "containedTags", "absences",
    ]

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let raw = try encoder().encode(value)
        let tree = try JSONDecoder().decode(JSONValue.self, from: raw)
        return try encoder().encode(normalise(tree, key: nil))
    }

    static func encode(tree: JSONValue) throws -> Data {
        try encoder().encode(tree)
    }

    private static func normalise(_ value: JSONValue, key: String?) -> JSONValue {
        switch value {
        case .object(let dictionary):
            var result: [String: JSONValue] = [:]
            for (name, child) in dictionary { result[name] = normalise(child, key: name) }
            return .object(result)
        case .array(let items):
            let children = items.map { normalise($0, key: nil) }
            if let key, setKeys.contains(key) {
                return .array(children.sorted { Self.sortKey($0) < Self.sortKey($1) })
            }
            return .array(children)
        default:
            return value
        }
    }

    private static func sortKey(_ value: JSONValue) -> String {
        if case .string(let text) = value { return text }
        if let data = try? encoder().encode(value) { return String(decoding: data, as: UTF8.self) }
        return ""
    }
}

/// ISO-8601 instants with or without fractional seconds.
enum ISODate {
    static func parse(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}
