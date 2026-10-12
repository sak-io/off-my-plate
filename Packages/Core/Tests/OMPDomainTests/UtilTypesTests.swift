import Foundation
import OMPDomain
import Testing

@Suite("Weekday")
struct WeekdayTests {
    @Test("ISO numbers run Monday = 1 to Sunday = 7 and map back")
    func isoNumbers() {
        #expect(Weekday.allCases.map(\.isoNumber) == [1, 2, 3, 4, 5, 6, 7])
        for day in Weekday.allCases {
            #expect(Weekday(isoNumber: day.isoNumber) == day)
        }
        #expect(Weekday(isoNumber: 0) == nil)
        #expect(Weekday(isoNumber: 8) == nil)
    }

    @Test("ordering is Monday first")
    func ordering() {
        #expect(Weekday.monday < Weekday.sunday)
        #expect(Weekday.allCases.sorted() == Weekday.allCases)
    }

    @Test("the default school week is Monday to Friday (AC-7.2)")
    func schoolWeek() {
        #expect(Weekday.schoolWeek == [.monday, .tuesday, .wednesday, .thursday, .friday])
    }

    @Test("encodes as the case name")
    func codable() throws {
        let data = try JSONEncoder().encode([Weekday.wednesday])
        #expect(String(decoding: data, as: UTF8.self) == "[\"wednesday\"]")
    }
}

@Suite("DomainClock")
struct DomainClockTests {
    @Test("today uses the clock's own time zone")
    func todayUsesClockTimeZone() throws {
        let instant = Date(timeIntervalSince1970: 1_791_763_200 - 3_600)  // 2026-10-11T23:00Z
        let utcZone = try #require(TimeZone(secondsFromGMT: 0))
        let indiaZone = try #require(TimeZone(secondsFromGMT: 19_800))
        let utc = FixedClock(now: instant, timeZone: utcZone)
        let india = FixedClock(now: instant, timeZone: indiaZone)
        #expect(utc.today == LocalDate(year: 2026, month: 10, day: 11))
        #expect(india.today == LocalDate(year: 2026, month: 10, day: 12))
    }

    @Test("SystemClock reports the time zone it was given and a current instant")
    func systemClock() throws {
        let zone = try #require(TimeZone(secondsFromGMT: 3_600))
        let clock = SystemClock(timeZone: zone)
        let before = Date()
        let now = clock.now
        let after = Date()
        #expect(clock.timeZone == zone)
        #expect(before <= now && now <= after)
    }
}

@Suite("EntityID")
struct EntityIDTests {
    @Test("encodes as a bare string and decodes back")
    func codable() throws {
        let id: RecipeID = "dal-tadka"
        let data = try JSONEncoder().encode([id])
        #expect(String(decoding: data, as: UTF8.self) == "[\"dal-tadka\"]")
        #expect(try JSONDecoder().decode([RecipeID].self, from: data) == [id])
    }

    @Test("decoding an empty identifier fails")
    func rejectsEmpty() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([MemberID].self, from: Data("[\"\"]".utf8))
        }
    }

    @Test("encoding an empty identifier throws, so one can never be stored")
    func emptyDoesNotEncode() {
        #expect(throws: EncodingError.self) {
            try JSONEncoder().encode([MemberID("")])
        }
    }

    @Test("generated identifiers are lowercased UUIDs and unique")
    func generate() {
        let first = MemberID.generate()
        let second = MemberID.generate()
        #expect(first != second)
        #expect(first.rawValue == first.rawValue.lowercased())
        #expect(UUID(uuidString: first.rawValue) != nil)
    }

    @Test("orders by raw value")
    func ordering() {
        let ids: [RecipeID] = ["upma", "aloo-paratha", "poha"]
        #expect(ids.sorted() == ["aloo-paratha", "poha", "upma"])
    }
}
