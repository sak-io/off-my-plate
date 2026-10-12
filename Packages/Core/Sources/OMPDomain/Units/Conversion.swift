/// Unit factors and conversions (plan section 10, task T07).
///
/// Within a dimension every unit converts through the dimension's base unit: grams for mass,
/// millilitres for volume, pieces for count. Kitchen measures are metric: tsp = 5 ml,
/// tbsp = 15 ml, cup = 240 ml. Across dimensions a conversion goes through mass, using the
/// ingredient's density (`gramsPerMl`) or piece weight (`gramsPerPiece`). Non-quantified
/// units ("pinch", "to taste") never convert.
extension MeasureUnit {
    /// Whether the unit carries an amount. False for `pinch` and `toTaste`.
    public var isQuantified: Bool { dimension != .unquantified }

    /// The base unit of this unit's dimension (`g`, `ml`, `piece`); nil when non-quantified.
    public var baseUnit: MeasureUnit? {
        switch dimension {
        case .mass: return .gram
        case .volume: return .millilitre
        case .count: return .piece
        case .unquantified: return nil
        }
    }

    /// How many base units one of this unit is; nil when non-quantified.
    public var baseUnitsPerUnit: Double? {
        switch self {
        case .gram, .millilitre, .piece: return 1
        case .kilogram, .litre: return 1000
        case .teaspoon: return 5
        case .tablespoon: return 15
        case .cup: return 240
        case .dozen: return 12
        case .pinch, .toTaste: return nil
        }
    }
}

/// The per-ingredient facts that allow cross-dimension conversion.
///
/// Taken as a value rather than an `Ingredient` so arithmetic does not depend on the recipe
/// library. A factor that is missing, zero, negative or not finite is treated as unknown.
public struct ConversionProfile: Sendable, Hashable {
    /// Grams per millilitre (volume <-> mass).
    public let gramsPerMl: Double?
    /// Grams per piece (count <-> mass).
    public let gramsPerPiece: Double?

    /// No cross-dimension conversion: only same-dimension conversions succeed.
    public static let none = ConversionProfile()

    public init(gramsPerMl: Double? = nil, gramsPerPiece: Double? = nil) {
        self.gramsPerMl = ConversionProfile.usable(gramsPerMl)
        self.gramsPerPiece = ConversionProfile.usable(gramsPerPiece)
    }

    /// The profile of a taxonomy ingredient.
    public init(ingredient: Ingredient) {
        self.init(gramsPerMl: ingredient.gramsPerMl, gramsPerPiece: ingredient.gramsPerPiece)
    }

    private static func usable(_ factor: Double?) -> Double? {
        guard let factor, factor.isFinite, factor > 0 else { return nil }
        return factor
    }

    /// Grams per base unit of `dimension`, or nil when unknown for this ingredient.
    func gramsPerBaseUnit(of dimension: MeasureDimension) -> Double? {
        switch dimension {
        case .mass: return 1
        case .volume: return gramsPerMl
        case .count: return gramsPerPiece
        case .unquantified: return nil
        }
    }

    /// Whether an amount in `from` can be expressed in `to` for this ingredient.
    public func canConvert(from: MeasureUnit, to: MeasureUnit) -> Bool {
        factor(from: from, to: to) != nil
    }

    /// The multiplier taking an amount in `from` to an amount in `to`, or nil when the two
    /// units are not convertible for this ingredient.
    public func factor(from: MeasureUnit, to: MeasureUnit) -> Double? {
        guard let fromBase = from.baseUnitsPerUnit, let toBase = to.baseUnitsPerUnit else {
            return nil
        }
        if from.dimension == to.dimension {
            return fromBase / toBase
        }
        guard let fromGrams = gramsPerBaseUnit(of: from.dimension),
              let toGrams = gramsPerBaseUnit(of: to.dimension)
        else { return nil }
        return fromBase * fromGrams / (toBase * toGrams)
    }
}
