import Foundation
import OMPDomain
import Testing

@Suite("ISOWeek")
struct ISOWeekTests {
    private func week(_ year: Int, _ month: Int, _ day: Int) throws -> ISOWeek {
        ISOWeek(containing: try #require(LocalDate(year: year, month: month, day: day)))
    }

    @Test("known dates, including weeks that belong to the neighbouring year")
    func knownDates() throws {
        #expect(try week(2026, 10, 12) == ISOWeek(year: 2026, week: 42))
        #expect(try week(2026, 1, 1) == ISOWeek(year: 2026, week: 1))
        #expect(try week(2025, 12, 29) == ISOWeek(year: 2026, week: 1))
        #expect(try week(2021, 1, 1) == ISOWeek(year: 2020, week: 53))
        #expect(try week(2024, 12, 30) == ISOWeek(year: 2025, week: 1))
        #expect(try week(2027, 1, 3) == ISOWeek(year: 2026, week: 53))
        #expect(try week(2008, 12, 29) == ISOWeek(year: 2009, week: 1))
        #expect(try week(2010, 1, 3) == ISOWeek(year: 2009, week: 53))
        #expect(try week(2026, 10, 12).description == "2026-W42")
        #expect(try week(2026, 1, 1).description == "2026-W01")
    }

    @Test("weeks start on Monday and advance by one (sweep 1999-2031)")
    func sweepIsConsistent() throws {
        let start = try #require(LocalDate(year: 1999, month: 1, day: 1))
        let end = try #require(LocalDate(year: 2031, month: 12, day: 31))
        var previous = ISOWeek(containing: start)
        var day = start.adding(days: 1)
        while day <= end {
            let current = ISOWeek(containing: day)
            if day.weekday == .monday {
                let nextInYear = ISOWeek(year: previous.year, week: previous.week + 1)
                let firstOfNext = ISOWeek(year: previous.year + 1, week: 1)
                #expect(current == nextInYear || current == firstOfNext, "\(day)")
                if current == firstOfNext { #expect(previous.week == 52 || previous.week == 53, "\(day)") }
            } else {
                #expect(current == previous, "\(day)")
            }
            previous = current
            day = day.adding(days: 1)
        }
    }

    @Test("an instant's week depends on the explicit time zone")
    func instantUsesTimeZone() throws {
        // Sunday 2026-10-18 20:00 UTC is already Monday in India (+05:30).
        let instant = Date(timeIntervalSince1970: 1_791_763_200 + 6 * 86_400 + 20 * 3_600)
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        let india = try #require(TimeZone(secondsFromGMT: 19_800))
        #expect(ISOWeek(containing: instant, in: utc) == ISOWeek(year: 2026, week: 42))
        #expect(ISOWeek(containing: instant, in: india) == ISOWeek(year: 2026, week: 43))
    }
}
