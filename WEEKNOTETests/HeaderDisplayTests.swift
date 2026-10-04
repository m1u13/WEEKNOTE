import XCTest
@testable import WEEKNOTE

final class HeaderDisplayTests: XCTestCase {
    private var tokyo: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(_ key: String, calendar: Calendar? = nil, hour: Int = 12) throws -> Date {
        let calendar = calendar ?? tokyo
        let day = try XCTUnwrap(HeaderDisplayConfiguration.date(from: key, calendar: calendar))
        return try XCTUnwrap(calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day))
    }

    func testWeekUsesSelectedDayAndISOYearBoundary() throws {
        let configuration = HeaderDisplayConfiguration()
        let reading = HeaderDisplayReading.make(configuration: configuration, selectedDay: try date("2021-01-01"), today: try date("2026-10-05"), calendar: tokyo)
        XCTAssertEqual(reading.value, "WEEK 53")
        XCTAssertNil(reading.unit)
    }

    func testDeadlineTodayIsZeroAndPastDateIsExplicitlyOverdue() throws {
        var configuration = HeaderDisplayConfiguration()
        configuration.mode = .deadline
        configuration.deadlineTitle = "試験"
        configuration.deadlineDay = "2026-10-10"
        let selected = try date("2027-01-01")
        let before = HeaderDisplayReading.make(configuration: configuration, selectedDay: selected, today: try date("2026-10-05", hour: 23), calendar: tokyo)
        XCTAssertEqual(before.number, 5)
        XCTAssertEqual(before.label, "試験まで")
        let same = HeaderDisplayReading.make(configuration: configuration, selectedDay: selected, today: try date("2026-10-10", hour: 23), calendar: tokyo)
        XCTAssertEqual(same.number, 0)
        XCTAssertEqual(same.label, "試験当日")
        let after = HeaderDisplayReading.make(configuration: configuration, selectedDay: selected, today: try date("2026-10-12"), calendar: tokyo)
        XCTAssertEqual(after.number, 2)
        XCTAssertEqual(after.label, "試験・目標日超過")
    }

    func testYearEndUsesCalendarDaysAndLeapYears() throws {
        var configuration = HeaderDisplayConfiguration()
        configuration.mode = .yearEnd
        for (day, expected) in [("2026-01-01", 364), ("2024-01-01", 365), ("2024-02-28", 307), ("2026-12-31", 0)] {
            let reference = try date(day, hour: 23)
            let reading = HeaderDisplayReading.make(configuration: configuration, selectedDay: reference, today: reference, calendar: tokyo)
            XCTAssertEqual(reading.number, expected, day)
        }
        let nextYear = try date("2027-01-01")
        let reading = HeaderDisplayReading.make(configuration: configuration, selectedDay: try date("2026-12-31"), today: nextYear, calendar: tokyo)
        XCTAssertEqual(reading.number, 364)
        XCTAssertEqual(reading.label, "2027年の終了まで")
    }

    func testElapsedStartsAtZeroAndFutureStartShowsRemainingDays() throws {
        var configuration = HeaderDisplayConfiguration()
        configuration.mode = .elapsed
        configuration.elapsedTitle = "学習"
        configuration.startDay = "2026-10-05"
        let selected = try date("2028-01-01")
        let before = HeaderDisplayReading.make(configuration: configuration, selectedDay: selected, today: try date("2026-10-03"), calendar: tokyo)
        XCTAssertEqual(before.number, 2)
        XCTAssertEqual(before.label, "学習・開始まで")
        let same = HeaderDisplayReading.make(configuration: configuration, selectedDay: selected, today: try date("2026-10-05"), calendar: tokyo)
        XCTAssertEqual(same.number, 0)
        let after = HeaderDisplayReading.make(configuration: configuration, selectedDay: selected, today: try date("2026-10-09"), calendar: tokyo)
        XCTAssertEqual(after.number, 4)
        XCTAssertEqual(after.label, "学習・開始から")
    }

    func testDayCountAcrossDaylightSavingChangesIsNotBasedOnSeconds() throws {
        var calendar = tokyo
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var configuration = HeaderDisplayConfiguration()
        configuration.mode = .deadline
        configuration.deadlineDay = "2026-03-09"
        let spring = HeaderDisplayReading.make(configuration: configuration, selectedDay: try date("2026-03-07", calendar: calendar), today: try date("2026-03-07", calendar: calendar), calendar: calendar)
        XCTAssertEqual(spring.number, 2)
        configuration.mode = .elapsed
        configuration.startDay = "2026-10-31"
        let autumn = HeaderDisplayReading.make(configuration: configuration, selectedDay: try date("2026-11-02", calendar: calendar), today: try date("2026-11-02", calendar: calendar), calendar: calendar)
        XCTAssertEqual(autumn.number, 2)
    }

    func testConfiguredCalendarDayStaysTheSameInAnotherTimeZone() throws {
        var configuration = HeaderDisplayConfiguration()
        configuration.mode = .deadline
        configuration.deadlineDay = "2026-10-06"
        var losAngeles = tokyo
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        for calendar in [tokyo, losAngeles] {
            let reference = try date("2026-10-05", calendar: calendar)
            XCTAssertEqual(HeaderDisplayReading.make(configuration: configuration, selectedDay: reference, today: reference, calendar: calendar).number, 1)
        }
    }

    func testModeChangesAndSerializationKeepBothConfiguredDates() throws {
        var configuration = HeaderDisplayConfiguration()
        configuration.mode = .elapsed
        configuration.deadlineTitle = "資格試験"
        configuration.deadlineDay = "2027-03-21"
        configuration.elapsedTitle = "学習"
        configuration.startDay = "2026-10-01"
        let roundTrip = HeaderDisplayPreference.decode(HeaderDisplayPreference.encode(configuration))
        XCTAssertEqual(roundTrip, configuration)
        var alternate = roundTrip
        alternate.mode = .deadline
        XCTAssertEqual(alternate.startDay, "2026-10-01")
        XCTAssertEqual(alternate.deadlineDay, "2027-03-21")
    }

    func testInvalidSettingsFallBackAndInvalidDatesAreNotNormalized() throws {
        let today = try date("2026-10-05")
        XCTAssertEqual(HeaderDisplayPreference.decode(Data("invalid".utf8), today: today).mode, .weekNumber)
        XCTAssertNil(HeaderDisplayConfiguration.date(from: "2026-02-29", calendar: tokyo))
        XCTAssertNil(HeaderDisplayConfiguration.date(from: "2026-2-10", calendar: tokyo))
        var configuration = HeaderDisplayConfiguration()
        configuration.deadlineDay = "2026-02-29"
        configuration.startDay = "2200-01-01"
        configuration.deadlineTitle = "  "
        let restored = HeaderDisplayPreference.decode(try JSONEncoder().encode(configuration), today: today)
        XCTAssertEqual(restored.deadlineDay, CalendarSupport.dayKey(today))
        XCTAssertEqual(restored.startDay, CalendarSupport.dayKey(today))
        XCTAssertEqual(restored.deadlineTitle, "目標")
    }
}
