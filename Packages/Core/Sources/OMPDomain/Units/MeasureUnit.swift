/// A unit of measure for recipe lines, pantry items and shopping items (plan section 6).
///
/// Named `MeasureUnit` rather than `Unit` so it cannot clash with Foundation's `Unit` class.
/// T03 fixes the cases and their dimension; conversions and quantity arithmetic are task T07.
/// Encodes as the raw value (`"g"`, `"tbsp"`, ...), which is also the seed JSON spelling.
public enum MeasureUnit: String, CaseIterable, Codable, Sendable, Hashable {
    case gram = "g"
    case kilogram = "kg"
    case millilitre = "ml"
    case litre = "l"
    case teaspoon = "tsp"
    case tablespoon = "tbsp"
    case cup = "cup"
    case piece = "piece"
    case dozen = "dozen"
    /// Non-quantified: never on the shopping list.
    case pinch = "pinch"
    /// Non-quantified: never on the shopping list.
    case toTaste = "toTaste"

    /// What this unit measures.
    public var dimension: MeasureDimension {
        switch self {
        case .gram, .kilogram: return .mass
        case .millilitre, .litre, .teaspoon, .tablespoon, .cup: return .volume
        case .piece, .dozen: return .count
        case .pinch, .toTaste: return .unquantified
        }
    }
}

/// What a unit measures. Units convert freely within a dimension; across dimensions only
/// through an ingredient's density or piece weight (task T07). Named to avoid Foundation's
/// `Dimension` class.
public enum MeasureDimension: String, CaseIterable, Codable, Sendable, Hashable {
    case mass
    case volume
    case count
    case unquantified
}
