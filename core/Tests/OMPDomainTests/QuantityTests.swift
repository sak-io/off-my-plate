import Foundation
import OMPDomain
import Testing

/// Relative-plus-absolute tolerance for floating-point comparisons.
private func approx(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-9) -> Bool {
    abs(lhs - rhs) <= tolerance * max(1, abs(lhs), abs(rhs))
}

private func approx(_ lhs: Quantity?, _ rhs: Quantity, tolerance: Double = 1e-9) -> Bool {
    guard let lhs else { return false }
    return lhs.unit == rhs.unit && approx(lhs.amount, rhs.amount, tolerance: tolerance)
}

/// SplitMix64: a fixed-seed generator so the property test is reproducible.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private let ghee = ConversionProfile(gramsPerMl: 0.91)
private let onion = ConversionProfile(gramsPerPiece: 150)
private let egg = ConversionProfile(gramsPerMl: 1.03, gramsPerPiece: 50)

@Suite("MeasureUnit factors")
struct MeasureUnitFactorTests {
    @Test("every quantified unit has a base unit and factor; non-quantified units have neither")
    func factorsCoverEveryCase() {
        for unit in MeasureUnit.allCases {
            #expect(unit.isQuantified == (unit.dimension != .unquantified))
            #expect((unit.baseUnit != nil) == unit.isQuantified)
            #expect((unit.baseUnitsPerUnit != nil) == unit.isQuantified)
            if let base = unit.baseUnit {
                #expect(base.dimension == unit.dimension)
                #expect(base.baseUnitsPerUnit == 1)
            }
        }
    }
}

@Suite("Quantity conversions")
struct QuantityConversionTests {
    struct Row: Sendable, CustomTestStringConvertible {
        let from: Quantity
        let to: MeasureUnit
        let profile: ConversionProfile
        let expected: Double
        var testDescription: String { "\(from.amount) \(from.unit.rawValue) -> \(to.rawValue)" }
    }

    static let table: [Row] = [
        // Same dimension (plan section 10: tsp 5, tbsp 15, cup 240).
        Row(from: Quantity(1, .kilogram), to: .gram, profile: .sameDimensionOnly, expected: 1000),
        Row(from: Quantity(250, .gram), to: .kilogram, profile: .sameDimensionOnly, expected: 0.25),
        Row(from: Quantity(1.5, .litre), to: .millilitre, profile: .sameDimensionOnly, expected: 1500),
        Row(from: Quantity(1, .teaspoon), to: .millilitre, profile: .sameDimensionOnly, expected: 5),
        Row(from: Quantity(1, .tablespoon), to: .teaspoon, profile: .sameDimensionOnly, expected: 3),
        Row(from: Quantity(1, .cup), to: .tablespoon, profile: .sameDimensionOnly, expected: 16),
        Row(from: Quantity(2, .cup), to: .litre, profile: .sameDimensionOnly, expected: 0.48),
        Row(from: Quantity(1, .dozen), to: .piece, profile: .sameDimensionOnly, expected: 12),
        Row(from: Quantity(18, .piece), to: .dozen, profile: .sameDimensionOnly, expected: 1.5),
        // Volume <-> mass through density.
        Row(from: Quantity(100, .millilitre), to: .gram, profile: ghee, expected: 91),
        Row(from: Quantity(2, .tablespoon), to: .gram, profile: ghee, expected: 27.3),
        Row(from: Quantity(91, .gram), to: .millilitre, profile: ghee, expected: 100),
        Row(from: Quantity(1, .cup), to: .kilogram, profile: ghee, expected: 0.2184),
        // Count <-> mass through piece weight.
        Row(from: Quantity(2, .piece), to: .gram, profile: onion, expected: 300),
        Row(from: Quantity(1.5, .kilogram), to: .piece, profile: onion, expected: 10),
        Row(from: Quantity(1, .dozen), to: .kilogram, profile: egg, expected: 0.6),
        // Count <-> volume needs both factors.
        Row(from: Quantity(1, .piece), to: .millilitre, profile: egg, expected: 50 / 1.03),
    ]

    @Test("conversion table", arguments: QuantityConversionTests.table)
    func conversionTable(row: Row) throws {
        let converted = try #require(row.from.converted(to: row.to, using: row.profile))
        #expect(converted.unit == row.to)
        #expect(approx(converted.amount, row.expected))
        // And back again.
        #expect(approx(converted.converted(to: row.from.unit, using: row.profile), row.from))
    }

    @Test("cross-dimension conversion without the factor is refused")
    func missingFactorRefused() {
        #expect(Quantity(1, .cup).converted(to: .gram) == nil)
        #expect(Quantity(2, .piece).converted(to: .gram, using: ghee) == nil)
        #expect(Quantity(100, .gram).converted(to: .millilitre, using: onion) == nil)
        #expect(Quantity(1, .piece).converted(to: .millilitre, using: onion) == nil)
        #expect(!ConversionProfile.sameDimensionOnly.canConvert(from: .litre, to: .kilogram))
    }

    @Test("zero, negative and non-finite factors count as unknown")
    func unusableFactors() {
        for bad in [0, -1, Double.nan, Double.infinity] {
            let profile = ConversionProfile(gramsPerMl: bad, gramsPerPiece: bad)
            #expect(profile.gramsPerMl == nil)
            #expect(profile.gramsPerPiece == nil)
            #expect(Quantity(1, .cup).converted(to: .gram, using: profile) == nil)
        }
    }

    @Test("a profile can be built from a taxonomy ingredient")
    func profileFromIngredient() {
        let ingredient = Ingredient(
            id: IngredientID("onion"), name: "Onion", tagStatus: .verified,
            aisle: .vegetablesAndFruit, defaultUnit: .piece, gramsPerPiece: 150,
            defaultLocation: .shelf
        )
        #expect(ConversionProfile(ingredient: ingredient) == onion)
    }

    @Test("non-quantified units never convert, except to themselves")
    func nonQuantifiedUnits() {
        let pinch = Quantity(3, .pinch)
        #expect(pinch.amount == 0)
        #expect(pinch.converted(to: .pinch) == pinch)
        #expect(pinch.converted(to: .toTaste, using: egg) == nil)
        #expect(pinch.converted(to: .gram, using: egg) == nil)
        #expect(Quantity(5, .gram).converted(to: .toTaste, using: egg) == nil)
        #expect(Quantity(1, .toTaste).inBaseUnit == Quantity(0, .toTaste))
    }

    @Test("inBaseUnit normalises to g, ml and piece")
    func baseUnit() {
        #expect(approx(Quantity(2, .kilogram).inBaseUnit, Quantity(2000, .gram)))
        #expect(approx(Quantity(3, .tablespoon).inBaseUnit, Quantity(45, .millilitre)))
        #expect(approx(Quantity(2, .dozen).inBaseUnit, Quantity(24, .piece)))
    }
}

@Suite("Quantity arithmetic")
struct QuantityArithmeticTests {
    @Test("negative and non-finite amounts clamp to zero on creation and decoding")
    func clampOnCreation() throws {
        #expect(Quantity(-2, .gram).amount == 0)
        #expect(Quantity(.nan, .gram).amount == 0)
        #expect(Quantity(-.infinity, .gram).amount == 0)
        #expect(Quantity(.infinity, .litre).amount == Double.greatestFiniteMagnitude)
        let json = Data(#"{"amount":-5,"unit":"kg"}"#.utf8)
        let decoded = try JSONDecoder().decode(Quantity.self, from: json)
        #expect(decoded == Quantity(0, .kilogram))
    }

    @Test("Codable round trip")
    func codableRoundTrip() throws {
        let quantity = Quantity(1.25, .cup)
        let data = try JSONEncoder().encode(quantity)
        #expect(try JSONDecoder().decode(Quantity.self, from: data) == quantity)
    }

    @Test("adding converts into the left-hand unit")
    func addition() {
        #expect(approx(Quantity(1, .kilogram).adding(Quantity(250, .gram)), Quantity(1.25, .kilogram)))
        #expect(approx(Quantity(1, .tablespoon).adding(Quantity(1, .teaspoon)), Quantity(4.0 / 3.0, .tablespoon)))
        #expect(approx(Quantity(200, .gram).adding(Quantity(1, .piece), using: onion), Quantity(350, .gram)))
    }

    @Test("non-convertible quantities are not combined")
    func nonConvertibleNotCombined() {
        #expect(Quantity(200, .gram).adding(Quantity(1, .piece)) == nil)
        #expect(Quantity(1, .cup).subtracting(Quantity(100, .gram)) == nil)
        #expect(Quantity(1, .pinch).adding(Quantity(1, .toTaste)) == nil)
        #expect(Quantity(1, .gram).adding(Quantity(1, .pinch)) == nil)
        #expect(Quantity(1, .toTaste).adding(Quantity(1, .toTaste)) == Quantity(0, .toTaste))
    }

    @Test("subtraction clamps at zero, never negative (AC-9.6)")
    func subtractionClamps() {
        #expect(approx(Quantity(500, .gram).subtracting(Quantity(200, .gram)), Quantity(300, .gram)))
        #expect(Quantity(500, .gram).subtracting(Quantity(1, .kilogram)) == Quantity(0, .gram))
        #expect(Quantity(1, .piece).subtracting(Quantity(1, .kilogram), using: onion) == Quantity(0, .piece))
        #expect(Quantity(0, .gram).isZero)
        #expect(!Quantity(0, .toTaste).isZero)
    }

    @Test("0.1 kg + 0.2 kg - 300 g is exactly zero (relative-epsilon snap)")
    func subtractionSnapsRoundingNoiseToZero() throws {
        let sum = try #require(Quantity(0.1, .kilogram).adding(Quantity(0.2, .kilogram)))
        let rest = try #require(sum.subtracting(Quantity(300, .gram)))
        #expect(rest == Quantity(0, .kilogram))
        #expect(rest.isZero)
    }

    @Test("1 l - 1000/15 tbsp is exactly zero, in a total too, with no excess")
    func litreMinusTablespoonsIsZero() throws {
        let tbsp = Quantity(1000.0 / 15.0, .tablespoon)
        let rest = try #require(Quantity(1, .litre).subtracting(tbsp))
        #expect(rest == Quantity(0, .litre))

        var total = QuantityTotal([Quantity(1, .litre)])
        let excess = total.subtract(tbsp)
        #expect(total.isZero)
        #expect(excess == Quantity(0, .tablespoon))
    }

    @Test("a real difference above the epsilon is kept")
    func smallRealDifferenceKept() throws {
        let rest = try #require(Quantity(1, .kilogram).subtracting(Quantity(999, .gram)))
        #expect(approx(rest.amount, 0.001))
    }

    @Test("scaling multiplies by servings and clamps at zero (AC-6.4)")
    func scaling() {
        #expect(approx(Quantity(150, .gram).scaled(by: 2.5), Quantity(375, .gram)))
        #expect(Quantity(150, .gram).scaled(by: 0) == Quantity(0, .gram))
        #expect(Quantity(150, .gram).scaled(by: -1) == Quantity(0, .gram))
        #expect(Quantity(150, .gram).scaled(by: .nan) == Quantity(0, .gram))
        #expect(Quantity(2, .kilogram).scaled(by: .greatestFiniteMagnitude).amount == Double.greatestFiniteMagnitude)
        #expect(Quantity(2, .kilogram).scaled(by: .infinity).amount == Double.greatestFiniteMagnitude)
        #expect(Quantity(0, .kilogram).scaled(by: .infinity) == Quantity(0, .kilogram))
        #expect(Quantity(1, .pinch).scaled(by: 4) == Quantity(0, .pinch))
    }

    @Test("property: a + b - b is a, within tolerance (seeded)")
    func addThenSubtractRoundTrips() throws {
        var rng = SplitMix64(state: 0x0FF_0B1A7E)
        let quantified = MeasureUnit.allCases.filter(\.isQuantified)
        for _ in 0..<1000 {
            let unitA = quantified.randomElement(using: &rng)!
            let unitB = quantified.randomElement(using: &rng)!
            let a = Quantity(Double.random(in: 0...5000, using: &rng), unitA)
            let b = Quantity(Double.random(in: 0...5000, using: &rng), unitB)
            guard let sum = a.adding(b, using: egg) else {
                Issue.record("egg profile converts every quantified pair: \(unitA) \(unitB)")
                continue
            }
            let back = try #require(sum.subtracting(b, using: egg))
            // Subtraction snaps differences within relativeEpsilon of the sum to zero, so the
            // property holds to that bound (plus float noise).
            let bound = 2 * Quantity.relativeEpsilon * max(1, sum.amount)
            #expect(abs(back.amount - a.amount) <= bound, "\(a) + \(b) - \(b) = \(back)")
        }
    }
}

@Suite("QuantityTotal")
struct QuantityTotalTests {
    @Test("convertible quantities merge into the first part's unit")
    func mergesConvertible() throws {
        let total = QuantityTotal([Quantity(1, .kilogram), Quantity(500, .gram), Quantity(250, .gram)])
        #expect(total.parts.count == 1)
        let first: Quantity = try #require(total.parts.first)
        #expect(approx(first, Quantity(1.75, .kilogram)))
    }

    @Test("non-convertible quantities are kept as separate parts (AC-10.1)")
    func keepsNonConvertibleApart() {
        let total = QuantityTotal([
            Quantity(2, .piece), Quantity(100, .gram), Quantity(1, .piece),
            Quantity(1, .toTaste), Quantity(1, .pinch), Quantity(1, .tablespoon),
        ])
        #expect(total.parts.count == 5)
        #expect(approx(total.parts[0], Quantity(3, .piece)))
        #expect(total.quantifiedParts.count == 3)
    }

    @Test("with a piece weight, pieces and grams merge")
    func mergesWithProfile() {
        let total = QuantityTotal(profile: onion, [Quantity(2, .piece), Quantity(150, .gram)])
        #expect(total.parts.count == 1)
        #expect(approx(total.parts[0], Quantity(3, .piece)))
    }

    @Test("needed minus pantry clamps at zero and reports the excess")
    func subtractPantry() {
        var needed = QuantityTotal([Quantity(1, .kilogram), Quantity(2, .piece)])
        let leftover = needed.subtract(Quantity(400, .gram))
        #expect(approx(needed.parts[0], Quantity(0.6, .kilogram)))
        #expect(leftover == Quantity(0, .gram))

        let excess = needed.subtract(Quantity(1, .kilogram))
        #expect(needed.parts[0] == Quantity(0, .kilogram))
        // The excess is reported in the subtracted quantity's unit (here kg).
        #expect(approx(excess, Quantity(0.4, .kilogram)))

        let unmatched = needed.subtract(Quantity(1, .cup))
        #expect(unmatched == Quantity(1, .cup))
        #expect(needed.parts.count == 2)
        #expect(!needed.isZero)
        _ = needed.subtract(Quantity(5, .piece))
        #expect(needed.isZero)
    }

    @Test("scaling a total scales every part")
    func scaleTotal() {
        let total = QuantityTotal([Quantity(100, .gram), Quantity(1, .piece)]).scaled(by: 3)
        #expect(approx(total.parts[0], Quantity(300, .gram)))
        #expect(approx(total.parts[1], Quantity(3, .piece)))
    }
}
