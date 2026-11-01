import Foundation

/// An ISO 8601 week (week-numbering year and week 1...53), used for the learning threshold
/// ("across at least 2 weeks", ADR 0013) and the prompt caps (AC-7.4, AC-12.2).
///
/// Computed with pure integer arithmetic on `LocalDate` (no `Calendar`), so the answer is the
/// same on every platform and in every locale (ADR 0005). ISO weeks start on Monday, and week 1
/// is the week that contains the year's first Thursday.
public struct ISOWeek: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    /// The ISO week-numbering year (can differ from the calendar year around 1 January).
    public let year: Int
    /// 1...53.
    public let week: Int

    /// A week by number. Not validated (week 53 exists only in some years); use
    /// `init(containing:)` to compute one.
    public init(year: Int, week: Int) {
        self.year = year
        self.week = week
    }

    /// The ISO week that contains `date`.
    public init(containing date: LocalDate) {
        // The Thursday of the same Monday-based week decides the ISO year.
        let thursday = date.adding(days: 4 - date.weekday.isoNumber)
        let isoYear = thursday.year
        // Every year has a 1 January, so this cannot fail for a year in LocalDate.yearRange.
        let januaryFirst = LocalDate(daysSinceEpoch: thursday.daysSinceEpoch - (thursday.isoDayOfYear - 1))
        self.year = isoYear
        self.week = thursday.daysSince(januaryFirst) / 7 + 1
    }

    /// The ISO week containing the instant `date` in `timeZone` (the time zone is explicit,
    /// ADR 0005).
    public init(containing date: Date, in timeZone: TimeZone) {
        self.init(containing: LocalDate(date, in: timeZone))
    }

    public static func < (lhs: ISOWeek, rhs: ISOWeek) -> Bool {
        (lhs.year, lhs.week) < (rhs.year, rhs.week)
    }

    /// `YYYY-Www`, for example `2026-W42`.
    public var description: String {
        let weekText = week < 10 ? "0\(week)" : "\(week)"
        return "\(year)-W\(weekText)"
    }
}

extension LocalDate {
    /// 1 for 1 January ... 365 or 366 for 31 December.
    fileprivate var isoDayOfYear: Int {
        var total = day
        var m = 1
        while m < month {
            total += LocalDate.daysInMonth(year: year, month: m)
            m += 1
        }
        return total
    }
}
