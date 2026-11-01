import Foundation
import OMPDomain
import Testing

@Suite("LocalDate")
struct LocalDateTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> LocalDate {
        try #require(LocalDate(year: year, month: month, day: day))
    }

    // MARK: Validation

    @Test("rejects days that do not exist")
    func rejectsInvalidDays() {
        #expect(LocalDate(year: 2026, month: 2, day: 29) == nil)
        #expect(LocalDate(year: 2026, month: 4, day: 31) == nil)
        #expect(LocalDate(year: 2026, month: 13, day: 1) == nil)
        #expect(LocalDate(year: 2026, month: 0, day: 1) == nil)
        #expect(LocalDate(year: 2026, month: 1, day: 0) == nil)
        #expect(LocalDate(year: 0, month: 1, day: 1) == nil)
        #expect(LocalDate(year: 10_000, month: 1, day: 1) == nil)
    }

    @Test("accepts 29 February only in leap years (div by 4, not 100 unless 400)")
    func leapDayRule() {
        #expect(LocalDate(year: 2024, month: 2, day: 29) != nil)
        #expect(LocalDate(year: 2028, month: 2, day: 29) != nil)
        #expect(LocalDate(year: 2000, month: 2, day: 29) != nil)
        #expect(LocalDate(year: 1900, month: 2, day: 29) == nil)
        #expect(LocalDate(year: 2100, month: 2, day: 29) == nil)
        #expect(LocalDate.isLeapYear(2024))
        #expect(!LocalDate.isLeapYear(2026))
    }

    // MARK: Day count

    @Test("1970-01-01 is day 0 and known dates have known day counts")
    func epochDayCounts() throws {
        #expect(try date(1970, 1, 1).daysSinceEpoch == 0)
        #expect(try date(1969, 12, 31).daysSinceEpoch == -1)
        #expect(try date(2000, 3, 1).daysSinceEpoch == 11_017)
        // 2026-10-12T00:00:00Z is 1_791_763_200 seconds after the epoch.
        #expect(try date(2026, 10, 12).daysSinceEpoch == 1_791_763_200 / 86_400)
    }

    @Test("day count and date round-trip for every day from 1999 to 2031")
    func dayCountRoundTrip() throws {
        let start = try date(1999, 1, 1).daysSinceEpoch
        let end = try date(2031, 12, 31).daysSinceEpoch
        var previous: LocalDate?
        for days in start...end {
            let value = LocalDate(daysSinceEpoch: days)
            #expect(value.daysSinceEpoch == days)
            #expect(LocalDate(year: value.year, month: value.month, day: value.day) == value)
            if let previous {
                #expect(previous < value)
            }
            previous = value
        }
    }

    // MARK: Arithmetic across boundaries

    struct AddDaysCase: Sendable {
        let from: String
        let days: Int
        let expected: String
    }

    static let addDaysCases: [AddDaysCase] = [
        AddDaysCase(from: "2026-01-31", days: 1, expected: "2026-02-01"),
        AddDaysCase(from: "2026-02-28", days: 1, expected: "2026-03-01"),
        AddDaysCase(from: "2024-02-28", days: 1, expected: "2024-02-29"),
        AddDaysCase(from: "2024-02-29", days: 1, expected: "2024-03-01"),
        AddDaysCase(from: "2000-02-28", days: 1, expected: "2000-02-29"),
        AddDaysCase(from: "2100-02-28", days: 1, expected: "2100-03-01"),
        AddDaysCase(from: "2026-12-31", days: 1, expected: "2027-01-01"),
        AddDaysCase(from: "2027-01-01", days: -1, expected: "2026-12-31"),
        AddDaysCase(from: "2024-03-01", days: -1, expected: "2024-02-29"),
        AddDaysCase(from: "2026-10-12", days: 6, expected: "2026-10-18"),
        AddDaysCase(from: "2026-12-28", days: 7, expected: "2027-01-04"),
        AddDaysCase(from: "2024-01-01", days: 366, expected: "2025-01-01"),
        AddDaysCase(from: "2025-01-01", days: 365, expected: "2026-01-01"),
        AddDaysCase(from: "2026-10-12", days: 0, expected: "2026-10-12"),
    ]

    @Test("adding days crosses month, year and leap boundaries", arguments: LocalDateTests.addDaysCases)
    func addingDays(testCase: AddDaysCase) throws {
        let start = try #require(LocalDate(isoString: testCase.from))
        let end = try #require(LocalDate(isoString: testCase.expected))
        #expect(start.adding(days: testCase.days) == end)
        #expect(end.daysSince(start) == testCase.days)
        #expect(start.daysSince(end) == -testCase.days)
    }

    @Test("daysSince counts 180 vs 181 days exactly across a leap day")
    func daysSinceAcrossLeapYear() throws {
        let confirmed = try date(2028, 1, 1)
        #expect(try date(2028, 6, 29).daysSince(confirmed) == 180)
        #expect(try date(2028, 6, 30).daysSince(confirmed) == 181)
    }

    // MARK: Weekday

    @Test("weekday of known dates")
    func weekdays() throws {
        #expect(try date(1970, 1, 1).weekday == .thursday)
        #expect(try date(2026, 10, 12).weekday == .monday)
        #expect(try date(2026, 10, 18).weekday == .sunday)
        #expect(try date(2024, 2, 29).weekday == .thursday)
        #expect(try date(2000, 1, 1).weekday == .saturday)
        #expect(try date(1969, 12, 31).weekday == .wednesday)
    }

    @Test("seven consecutive days cover every weekday once, in order")
    func weekdaysCycle() throws {
        let monday = try date(2026, 10, 12)
        let days = (0..<7).map { monday.adding(days: $0).weekday }
        #expect(days == Weekday.allCases)
    }

    // MARK: Conversion from an instant

    @Test("the day of an instant depends on the explicit time zone")
    func dayOfInstantDependsOnTimeZone() throws {
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        let india = try #require(TimeZone(secondsFromGMT: 19_800))  // +05:30
        let westCoast = try #require(TimeZone(secondsFromGMT: -25_200))  // -07:00
        // 2026-10-11T20:00:00Z
        let instant = Date(timeIntervalSince1970: 1_791_763_200 - 4 * 3_600)
        let october11 = try date(2026, 10, 11)
        let october12 = try date(2026, 10, 12)
        #expect(LocalDate(instant, in: utc) == october11)
        #expect(LocalDate(instant, in: india) == october12)
        #expect(LocalDate(instant, in: westCoast) == october11)
    }

    @Test("midnight belongs to the new day; one second before belongs to the old one")
    func midnightBoundary() throws {
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        let midnight = Date(timeIntervalSince1970: 1_791_763_200)
        let october11 = try date(2026, 10, 11)
        let october12 = try date(2026, 10, 12)
        #expect(LocalDate(midnight, in: utc) == october12)
        #expect(LocalDate(midnight.addingTimeInterval(-1), in: utc) == october11)
    }

    @Test("instants before 1970 round down to the right day")
    func instantsBeforeEpoch() throws {
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        let newYearsEve = try date(1969, 12, 31)
        #expect(LocalDate(Date(timeIntervalSince1970: -1), in: utc) == newYearsEve)
    }

    // MARK: Text and Codable

    @Test("isoString is zero padded and parses back")
    func isoString() throws {
        let value = try date(987, 3, 4)
        #expect(value.isoString == "0987-03-04")
        #expect(LocalDate(isoString: "0987-03-04") == value)
        #expect(value.description == "0987-03-04")
    }

    @Test(
        "isoString parsing is strict",
        arguments: ["", "2026-1-01", "2026/10/12", "2026-10-12T00:00", "\u{FF12}026-10-12", "2026-02-30", "+026-10-12"]
    )
    func strictParsing(text: String) {
        #expect(LocalDate(isoString: text) == nil)
    }

    @Test("encodes as a bare YYYY-MM-DD string and decodes back")
    func codable() throws {
        let value = try date(2024, 2, 29)
        let data = try JSONEncoder().encode([value])
        #expect(String(decoding: data, as: UTF8.self) == "[\"2024-02-29\"]")
        #expect(try JSONDecoder().decode([LocalDate].self, from: data) == [value])
    }

    @Test("decoding an impossible date fails")
    func decodingRejectsInvalid() {
        let data = Data("[\"2026-02-29\"]".utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([LocalDate].self, from: data)
        }
    }
}
