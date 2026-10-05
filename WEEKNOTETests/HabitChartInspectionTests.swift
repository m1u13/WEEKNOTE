import XCTest
@testable import WEEKNOTE

final class HabitChartInspectionTests: XCTestCase {
    func testDayCenterUsesActualDaylightSavingInterval() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        for (month, day, duration) in [(3, 10, 23.0), (11, 3, 25.0)] {
            let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: month, day: day)))
            let center = HabitChartInspection.bucketCenter(date, unit: .day, calendar: calendar)
            XCTAssertEqual(center.timeIntervalSince(date), duration * 3600 / 2)
            XCTAssertTrue(calendar.isDate(center, inSameDayAs: date))
        }
    }

    func testMonthCenterUsesLeapFebruaryAndThirtyOneDayMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        for (month, days) in [(2, 29), (3, 31)] {
            let first = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: month, day: 1)))
            let middle = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: month, day: 20)))
            let center = HabitChartInspection.bucketCenter(middle, unit: .month, calendar: calendar)
            XCTAssertEqual(center.timeIntervalSince(first), Double(days) * 24 * 3600 / 2)
            XCTAssertEqual(calendar.component(.month, from: center), month)
        }
    }

    func testNearestBucketClampsToEdgesAndIgnoresInvalidPositions() {
        let first = Date(timeIntervalSince1970: 0)
        let middle = Date(timeIntervalSince1970: 100)
        let last = Date(timeIntervalSince1970: 200)
        let positions: [HabitChartInspection.Position] = [
            .init(date: first, x: 10), .init(date: middle, x: 30), .init(date: last, x: 50),
            .init(date: Date(timeIntervalSince1970: 300), x: .nan)
        ]
        XCTAssertEqual(HabitChartInspection.nearestDate(atX: -100, positions: positions), first)
        XCTAssertEqual(HabitChartInspection.nearestDate(atX: 29, positions: positions), middle)
        XCTAssertEqual(HabitChartInspection.nearestDate(atX: 100, positions: positions), last)
        XCTAssertNil(HabitChartInspection.nearestDate(atX: .nan, positions: positions))
        XCTAssertNil(HabitChartInspection.nearestDate(atX: 10, positions: []))
    }
}
