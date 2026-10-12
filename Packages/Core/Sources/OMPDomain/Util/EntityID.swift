import Foundation

/// A strongly typed identifier (plan section 3.1).
///
/// `Entity` is a phantom type: it is never stored, it only stops a `MemberID` from being
/// passed where a `RecipeID` is expected. The raw value is a plain string so that both
/// generated ids (lowercased UUIDs) and hand-written seed ids (`"paneer"`, `"vegetarian"`)
/// fit the same type.
///
/// It encodes as a bare JSON string (not `{"rawValue": ...}`). An empty id is invalid: encoding
/// one throws and decoding one fails, so an empty id can never be written to storage.
/// `Comparable` orders by raw value using Swift's `String` ordering (based on Unicode canonical
/// equivalence, independent of locale), which the planner uses as its final deterministic
/// tie-break.
public struct EntityID<Entity>: Hashable, Comparable, Codable, Sendable, CustomStringConvertible,
    ExpressibleByStringLiteral
{
    /// The raw identifier.
    public let rawValue: String

    /// Wraps a raw identifier. Callers are expected to pass a non-empty string.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Allows `let id: RecipeID = "dal-tadka"` in seed loaders and tests.
    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    /// A new random identifier: a lowercased UUID string.
    public static func generate() -> EntityID {
        EntityID(UUID().uuidString.lowercased())
    }

    public static func < (lhs: EntityID, rhs: EntityID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard !raw.isEmpty else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "An identifier must not be empty.")
        }
        self.rawValue = raw
    }

    public func encode(to encoder: any Encoder) throws {
        guard !rawValue.isEmpty else {
            throw EncodingError.invalidValue(
                rawValue,
                EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "An identifier must not be empty."))
        }
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Phantom tags for identifiers whose entity has no Swift type of its own.
public enum IDTag {
    /// All revisions of one plan share a series id (ADR 0008).
    public enum PlanSeries {}
    /// A cuisine/region from the seed catalog, for example `"southIndian"`.
    public enum Cuisine {}
    /// A contextual prompt, for example `"lunchbox"` (task T17).
    public enum Prompt {}
}
