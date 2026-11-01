import Foundation
import OMPDomain

/// Number, unit and date formatting of the Pantry screens. Rounding happens here, at display
/// only; stored quantities are never rounded (LESSONS: floating-point quantities).
enum PantryFormat {
    /// The units the form offers (screens.md S-21: g, kg, ml, L, pcs; "pack" has no
    /// `MeasureUnit`, so it is not offered: tracked deviation).
    static let formUnits: [MeasureUnit] = [.gram, .kilogram, .millilitre, .litre, .piece]

    /// The form units, plus `current` when an item already uses another unit (voice can store
    /// "a dozen eggs" or cups).
    static func units(including current: MeasureUnit) -> [MeasureUnit] {
        formUnits.contains(current) ? formUnits : formUnits + [current]
    }

    static func unitLabel(_ unit: MeasureUnit) -> String {
        switch unit {
        case .gram: return "g"
        case .kilogram: return "kg"
        case .millilitre: return "ml"
        case .litre: return "L"
        case .teaspoon: return "tsp"
        case .tablespoon: return "tbsp"
        case .cup: return "cup"
        case .piece: return "pcs"
        case .dozen: return "dozen"
        case .pinch: return "pinch"
        case .toTaste: return "to taste"
        }
    }

    /// "220", "2.5", "0.33": at most two decimals, no grouping, a dot as the separator.
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let style = FloatingPointFormatStyle<Double>(locale: Locale(identifier: "en_IN"))
            .grouping(.never)
            .precision(.fractionLength(0...2))
        return value.formatted(style)
    }

    /// "220 g".
    static func amount(_ value: Double, _ unit: MeasureUnit) -> String {
        "\(number(value)) \(unitLabel(unit))"
    }

    static func amount(_ quantity: Quantity) -> String {
        amount(quantity.amount, quantity.unit)
    }

    /// A typed amount: digits with a dot or a comma as the decimal separator. Nil unless it is
    /// a finite number of at least 0 and not absurdly large.
    static func parseAmount(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite, value >= 0, value <= 1_000_000_000
        else { return nil }
        return value
    }

    /// How much one tap of plus or minus changes an amount in `unit` on the cooked sheet.
    static func step(for unit: MeasureUnit) -> Double {
        switch unit {
        case .gram, .millilitre: return 10
        case .kilogram, .litre: return 0.5
        case .teaspoon, .tablespoon, .cup, .piece, .dozen, .pinch, .toTaste: return 1
        }
    }

    // MARK: Dates

    static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// Noon of `day` in `timeZone`, for a `DatePicker`.
    static func date(for day: LocalDate, in timeZone: TimeZone) -> Date {
        let components = DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)
        return calendar(timeZone).date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    static func weekdayName(_ day: LocalDate, in timeZone: TimeZone) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .omitted, calendar: calendar(timeZone), timeZone: timeZone)
            .weekday(.wide)
        return date(for: day, in: timeZone).formatted(style)
    }

    static func shortDate(_ day: LocalDate, in timeZone: TimeZone) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .omitted, calendar: calendar(timeZone), timeZone: timeZone)
            .day().month(.abbreviated)
        return date(for: day, in: timeZone).formatted(style)
    }
}
