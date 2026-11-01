import Foundation

/// A calendar day (proleptic Gregorian year, month, day) with no time and no time zone
/// (ADR 0005).
///
/// Plans, expiry dates and school days are about days, not instants. Arithmetic is pure
/// integer maths on a day count (days since 1970-01-01), so it gives the same answer on every
/// platform and in every locale. The only conversion from an instant is
/// `init(_:in:)`, which takes the time zone explicitly.
///
/// Encodes as an ISO 8601 calendar date string, `"2026-10-12"`. Years are limited to
/// 1...9999 so that the string always has four year digits.
public struct LocalDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// The supported years.
    public static let yearRange: ClosedRange<Int> = 1...9999

    /// A validated date, or `nil` if the combination does not exist (for example 2026-02-29).
    public init?(year: Int, month: Int, day: Int) {
        guard LocalDate.yearRange.contains(year), month >= 1, month <= 12, day >= 1,
            day <= LocalDate.daysInMonth(year: year, month: month)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// The date `days` days after 1970-01-01 (negative values are before it).
    ///
    /// - Precondition: the result's year is within `yearRange` (about +/- 2.9 million days
    ///   around 1970); a plan date outside it is a programming error.
    public init(daysSinceEpoch days: Int) {
        // Howard Hinnant's civil_from_days, valid for the whole proleptic Gregorian calendar.
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        precondition(LocalDate.yearRange.contains(year), "LocalDate year \(year) is out of range")
        self.year = year
        self.month = month
        self.day = day
    }

    /// The calendar day that contains `date` in `timeZone`.
    ///
    /// The time zone is a required argument on purpose: the core never reads the device's
    /// current time zone (ADR 0005). Callers pass the one from their `DomainClock`.
    public init(_ date: Date, in timeZone: TimeZone) {
        let offset = Double(timeZone.secondsFromGMT(for: date))
        let localSeconds = date.timeIntervalSince1970 + offset
        let days = Int((localSeconds / 86_400).rounded(.down))
        self.init(daysSinceEpoch: days)
    }

    /// Parses a strict ISO 8601 calendar date, `YYYY-MM-DD` (ASCII digits only).
    public init?(isoString: String) {
        let bytes = Array(isoString.utf8)
        let dash = UInt8(ascii: "-")
        guard bytes.count == 10, bytes[4] == dash, bytes[7] == dash else { return nil }

        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for index in range {
                let byte = bytes[index]
                guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else { return nil }
                value = value * 10 + Int(byte - UInt8(ascii: "0"))
            }
            return value
        }

        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10) else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    /// Days since 1970-01-01 (Howard Hinnant's days_from_civil).
    public var daysSinceEpoch: Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let shiftedMonth = (month + 9) % 12  // March = 0 ... February = 11
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The date `days` days later (or earlier, if negative).
    public func adding(days: Int) -> LocalDate {
        LocalDate(daysSinceEpoch: daysSinceEpoch + days)
    }

    /// Whole days from `other` to `self`: positive when `self` is later.
    public func daysSince(_ other: LocalDate) -> Int {
        daysSinceEpoch - other.daysSinceEpoch
    }

    /// The day of the week. 1970-01-01 was a Thursday.
    public var weekday: Weekday {
        let mondayBased = ((daysSinceEpoch + 3) % 7 + 7) % 7
        return Weekday.allCases[mondayBased]
    }

    /// `YYYY-MM-DD`.
    public var isoString: String {
        LocalDate.zeroPadded(year, width: 4) + "-" + LocalDate.zeroPadded(month, width: 2) + "-"
            + LocalDate.zeroPadded(day, width: 2)
    }

    public var description: String {
        isoString
    }

    /// Gregorian leap year rule.
    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    /// Number of days in `month` (1...12) of `year`; 0 for an invalid month.
    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeapYear(year) ? 29 : 28
        default: return 0
        }
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let date = LocalDate(isoString: text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected a YYYY-MM-DD date, got '\(text)'.")
        }
        self = date
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }

    private static func zeroPadded(_ value: Int, width: Int) -> String {
        let digits = String(value)
        guard digits.count < width else { return digits }
        return String(repeating: "0", count: width - digits.count) + digits
    }
}
