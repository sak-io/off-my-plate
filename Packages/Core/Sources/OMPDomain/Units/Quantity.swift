/// An amount in a unit (plan section 10, task T07).
///
/// Invariants, enforced by every initialiser including decoding:
/// - the amount is finite and never negative (negative or non-finite input becomes 0);
/// - a non-quantified unit ("pinch", "to taste") always has amount 0.
///
/// Arithmetic never goes below zero (AC-9.6) and returns nil when the two quantities cannot be
/// converted into each other, so callers keep them as separate lines (AC-10.1).
public struct Quantity: Sendable, Hashable, Codable {
    public let amount: Double
    public let unit: MeasureUnit

    public init(_ amount: Double, _ unit: MeasureUnit) {
        self.unit = unit
        if unit.isQuantified, amount.isFinite, amount > 0 {
            self.amount = amount
        } else {
            self.amount = 0
        }
    }

    private enum CodingKeys: String, CodingKey {
        case amount
        case unit
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            try container.decode(Double.self, forKey: .amount),
            try container.decode(MeasureUnit.self, forKey: .unit)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(amount, forKey: .amount)
        try container.encode(unit, forKey: .unit)
    }

    /// Whether the unit carries an amount (false for "pinch" and "to taste").
    public var isQuantified: Bool { unit.isQuantified }

    /// True when a quantified amount is zero. Non-quantified quantities are never "zero":
    /// "to taste" still means the ingredient is used.
    public var isZero: Bool { unit.isQuantified && amount == 0 }

    /// The same amount in `target`, or nil when not convertible with `profile`.
    /// Converting a non-quantified quantity to its own unit returns it unchanged.
    public func converted(to target: MeasureUnit, using profile: ConversionProfile = .none) -> Quantity? {
        if target == unit { return self }
        guard let factor = profile.factor(from: unit, to: target) else { return nil }
        return Quantity(amount * factor, target)
    }

    /// The same amount in the base unit of its dimension (g, ml, piece); self when
    /// non-quantified.
    public var inBaseUnit: Quantity {
        guard let base = unit.baseUnit else { return self }
        return converted(to: base) ?? self
    }

    /// Whether `other` can be combined with this quantity using `profile`.
    public func isCompatible(with other: Quantity, using profile: ConversionProfile = .none) -> Bool {
        other.unit == unit || profile.canConvert(from: other.unit, to: unit)
    }

    /// `self + other`, in this quantity's unit; nil when the units are not convertible.
    /// Adding two equal non-quantified units ("to taste" + "to taste") yields the same unit.
    public func adding(_ other: Quantity, using profile: ConversionProfile = .none) -> Quantity? {
        guard let other = other.converted(to: unit, using: profile) else { return nil }
        return Quantity(amount + other.amount, unit)
    }

    /// `self - other`, clamped at zero, in this quantity's unit; nil when not convertible.
    public func subtracting(_ other: Quantity, using profile: ConversionProfile = .none) -> Quantity? {
        guard let other = other.converted(to: unit, using: profile) else { return nil }
        return Quantity(amount - other.amount, unit)
    }

    /// The amount multiplied by `factor` (servings, portions), clamped at zero.
    /// A negative or non-finite factor gives zero.
    public func scaled(by factor: Double) -> Quantity {
        guard factor.isFinite, factor > 0 else { return Quantity(0, unit) }
        return Quantity(amount * factor, unit)
    }
}

/// A running total of one ingredient's quantities that keeps non-convertible amounts apart
/// (AC-6.4, AC-10.1): "2 piece + 100 g" stays two parts unless a piece weight is known.
///
/// Each added quantity merges into the first part it converts to, in that part's unit;
/// otherwise it starts a new part. Because convertibility through mass is an equivalence for
/// a fixed profile, no two parts are ever convertible into each other.
public struct QuantityTotal: Sendable, Hashable {
    public let profile: ConversionProfile
    /// The parts in first-seen order.
    public private(set) var parts: [Quantity]

    public init(profile: ConversionProfile = .none, _ quantities: [Quantity] = []) {
        self.profile = profile
        self.parts = []
        for quantity in quantities { add(quantity) }
    }

    /// The parts that carry an amount (what a shopping list may show).
    public var quantifiedParts: [Quantity] { parts.filter(\.isQuantified) }

    /// True when every quantified part is zero (non-quantified parts are ignored).
    public var isZero: Bool { quantifiedParts.allSatisfy(\.isZero) }

    public mutating func add(_ quantity: Quantity) {
        for index in parts.indices {
            if let sum = parts[index].adding(quantity, using: profile) {
                parts[index] = sum
                return
            }
        }
        parts.append(quantity)
    }

    /// Subtracts `quantity` from the part it converts to, clamped at zero. Returns the
    /// amount that could not be taken (in `quantity`'s unit): all of it when no part is
    /// compatible, otherwise any excess over that part.
    @discardableResult
    public mutating func subtract(_ quantity: Quantity) -> Quantity {
        for index in parts.indices {
            let part = parts[index]
            guard let wanted = quantity.converted(to: part.unit, using: profile),
                  let remaining = part.subtracting(wanted, using: profile)
            else { continue }
            parts[index] = remaining
            let excess = Quantity(wanted.amount - part.amount, part.unit)
            return excess.converted(to: quantity.unit, using: profile) ?? Quantity(0, quantity.unit)
        }
        return quantity
    }

    /// Every part multiplied by `factor`, clamped at zero.
    public func scaled(by factor: Double) -> QuantityTotal {
        var result = self
        result.parts = parts.map { $0.scaled(by: factor) }
        return result
    }
}
