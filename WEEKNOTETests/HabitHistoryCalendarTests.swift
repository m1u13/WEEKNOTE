import XCTest
@testable import WEEKNOTE

final class HabitHistoryCalendarTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: zone)!
        return value
    }

    func testYearHistoryIncludesEveryDayAndLeapDayWithoutAdjacentYears() throws {
        let calendar = calendar("Asia/Tokyo")
        for (year, expectedCount) in [(2024, 366), (2026, 365)] {
            let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: 10, day: 5)))
            let days = HabitHistoryCalendar.yearDays(containing: reference, calendar: calendar)
            XCTAssertEqual(days.count, expectedCount)
            XCTAssertEqual(Set(days).count, expectedCount)
            let first = calendar.dateComponents([.year, .month, .day], from: try XCTUnwrap(days.first))
            let last = calendar.dateComponents([.year, .month, .day], from: try XCTUnwrap(days.last))
            XCTAssertEqual(first.year, year); XCTAssertEqual(first.month, 1); XCTAssertEqual(first.day, 1)
            XCTAssertEqual(last.year, year); XCTAssertEqual(last.month, 12); XCTAssertEqual(last.day, 31)
            XCTAssertEqual(days.filter { calendar.component(.month, from: $0) == 2 && calendar.component(.day, from: $0) == 29 }.count, year == 2024 ? 1 : 0)
        }
    }

    func testHistoryPreservesLocalMidnightAcrossBothDaylightSavingChanges() throws {
        let calendar = calendar("America/Los_Angeles")
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 1, day: 1)))
        let days = HabitHistoryCalendar.yearDays(containing: reference, calendar: calendar)
        XCTAssertEqual(days.count, 366)
        XCTAssertTrue(days.allSatisfy { calendar.component(.hour, from: $0) == 0 })
        let march10 = try XCTUnwrap(days.first { calendar.component(.month, from: $0) == 3 && calendar.component(.day, from: $0) == 10 })
        let march11 = try XCTUnwrap(days.first { calendar.component(.month, from: $0) == 3 && calendar.component(.day, from: $0) == 11 })
        XCTAssertEqual(march11.timeIntervalSince(march10), 23 * 3600)
        let november3 = try XCTUnwrap(days.first { calendar.component(.month, from: $0) == 11 && calendar.component(.day, from: $0) == 3 })
        let november4 = try XCTUnwrap(days.first { calendar.component(.month, from: $0) == 11 && calendar.component(.day, from: $0) == 4 })
        XCTAssertEqual(november4.timeIntervalSince(november3), 25 * 3600)
    }
}
