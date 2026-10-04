import XCTest
@testable import WEEKNOTE

final class CalendarSupportTests: XCTestCase {
    private func day(_ key: String) throws -> Date { try XCTUnwrap(CalendarSupport.date(fromDayKey: key)) }

    func testISOWeekCrossesYearWithSevenConsecutiveDays() throws {
        let reference = try day("2021-01-01")
        XCTAssertEqual(CalendarSupport.weekNumber(reference), 53)
        XCTAssertEqual(CalendarSupport.weekYear(reference), 2020)
        let keys = CalendarSupport.weekDays(containing: reference).map(CalendarSupport.dayKey)
        XCTAssertEqual(keys, ["2020-12-28", "2020-12-29", "2020-12-30", "2020-12-31", "2021-01-01", "2021-01-02", "2021-01-03"])
    }

    func testLeapMonthAndMondayFirstMonthGrid() throws {
        let reference = try day("2024-02-15")
        XCTAssertEqual(CalendarSupport.monthDays(reference).count, 29)
        XCTAssertEqual(CalendarSupport.dayKey(CalendarSupport.monthDays(reference).last!), "2024-02-29")
        let grid = CalendarSupport.monthGridDays(reference)
        XCTAssertEqual(grid.count, 42)
        XCTAssertEqual(CalendarSupport.calendar.component(.weekday, from: grid[0]), 2)
        XCTAssertEqual(CalendarSupport.dayKey(grid[0]), "2024-01-29")
        XCTAssertEqual(CalendarSupport.dayKey(CalendarSupport.addingDays(1, to: try day("2024-02-28"))), "2024-02-29")
        XCTAssertEqual(CalendarSupport.dayKey(CalendarSupport.addingDays(1, to: try day("2024-02-29"))), "2024-03-01")
    }

    func testInvalidNumericDateIsNotNormalizedToAnotherDay() {
        XCTAssertNil(CalendarSupport.date(fromDayKey: "2026-02-29"))
        XCTAssertNil(CalendarSupport.date(fromDayKey: "2024-02-30"))
        XCTAssertNil(CalendarSupport.date(fromDayKey: "2026-13-01"))
        XCTAssertNil(CalendarSupport.date(fromDayKey: "2026--10-04"))
    }

    func testJapaneseQuickEntryCrossesYearAndPreservesTitle() throws {
        let parsed = CalendarSupport.parseQuickEntry("明日 １９：００ カレンダーを確認", relativeTo: try day("2026-12-31"))
        XCTAssertEqual(parsed.title, "カレンダーを確認")
        XCTAssertTrue(parsed.hasTime)
        let result = try XCTUnwrap(parsed.date)
        XCTAssertEqual(CalendarSupport.dayKey(result), "2027-01-01")
        XCTAssertEqual(CalendarSupport.calendar.component(.hour, from: result), 19)
        XCTAssertEqual(CalendarSupport.calendar.component(.minute, from: result), 0)
    }

    func testEnglishAndJapaneseDateFormats() throws {
        let reference = try day("2026-10-04")
        let english = CalendarSupport.parseQuickEntry("tomorrow 09:15 Meeting", relativeTo: reference)
        XCTAssertEqual(english.title, "Meeting")
        XCTAssertEqual(CalendarSupport.dayKey(try XCTUnwrap(english.date)), "2026-10-05")
        let japanese = CalendarSupport.parseQuickEntry("2027年3月21日 10時30分 予約", relativeTo: reference)
        XCTAssertEqual(japanese.title, "予約")
        XCTAssertEqual(CalendarSupport.dayKey(try XCTUnwrap(japanese.date)), "2027-03-21")
        XCTAssertEqual(CalendarSupport.calendar.component(.minute, from: japanese.date!), 30)
    }

    func testJapaneseTimeParticleDoesNotBecomePartOfTaskTitle() throws {
        let reference = try day("2026-10-04")
        let compact = CalendarSupport.parseQuickEntry("明日15時に打ち合わせ", relativeTo: reference)
        XCTAssertEqual(compact.title, "打ち合わせ")
        XCTAssertEqual(CalendarSupport.dayKey(try XCTUnwrap(compact.date)), "2026-10-05")
        XCTAssertEqual(CalendarSupport.calendar.component(.hour, from: compact.date!), 15)
        let colon = CalendarSupport.parseQuickEntry("明日 15:30から会議", relativeTo: reference)
        XCTAssertEqual(colon.title, "会議")
        XCTAssertEqual(CalendarSupport.calendar.component(.minute, from: colon.date!), 30)
    }

    func testQuickEntryLeavesAmbiguousOrInvalidTextIntact() throws {
        let reference = try day("2026-10-04")
        let invalid = CalendarSupport.parseQuickEntry("2026/2/30 25:00 予約", relativeTo: reference)
        XCTAssertEqual(invalid.title, "2026/2/30 25:00 予約")
        XCTAssertNil(invalid.date)
        XCTAssertFalse(invalid.hasTime)
        let sentence = CalendarSupport.parseQuickEntry("明日の資料を確認", relativeTo: reference)
        XCTAssertEqual(sentence.title, "明日の資料を確認")
        XCTAssertNil(sentence.date)
    }

    func testNextWeekWeekdayUsesFollowingISOWeek() throws {
        let parsed = CalendarSupport.parseQuickEntry("来週月曜日 14:00 レビュー", relativeTo: try day("2026-10-04"))
        XCTAssertEqual(CalendarSupport.dayKey(try XCTUnwrap(parsed.date)), "2026-10-05")
        XCTAssertEqual(parsed.title, "レビュー")
    }

    func testOfficialHolidayDataIncludesSubstituteAndCitizensHoliday() throws {
        let holidays = HolidayCalendar.shared
        XCTAssertEqual(holidays.coverageYears, 1955...2027)
        XCTAssertEqual(holidays.name(for: try day("2026-05-06")), "休日")
        XCTAssertEqual(holidays.name(for: try day("2026-09-22")), "休日")
        XCTAssertEqual(holidays.name(for: try day("2027-03-21")), "春分の日")
        XCTAssertEqual(holidays.name(for: try day("2027-03-22")), "休日")
        XCTAssertEqual(holidays.name(for: try day("2027-01-11")), "成人の日")
        XCTAssertFalse(holidays.isCovered(try day("2028-01-01")))
        XCTAssertNil(holidays.name(for: try day("2028-01-01")))
    }

    func testCompletionRequiresUserActionAndClassifiesBoundaryTimestamps() throws {
        let start = try day("2026-10-04").addingTimeInterval(9 * 3600)
        var task = PlannerTask(title: "予定", date: start, durationMinutes: 30, kind: .event)
        XCTAssertEqual(task.completionStatus, .pending)
        XCTAssertTrue(task.isOverdue(at: start.addingTimeInterval(3600)))
        task.isCompleted = true
        task.completedAt = start.addingTimeInterval(-1)
        XCTAssertEqual(task.completionStatus, .early)
        task.completedAt = start
        XCTAssertEqual(task.completionStatus, .onTime)
        task.completedAt = start.addingTimeInterval(1800)
        XCTAssertEqual(task.completionStatus, .onTime)
        task.completedAt = start.addingTimeInterval(1801)
        XCTAssertEqual(task.completionStatus, .late)
        XCTAssertFalse(task.isOverdue(at: start.addingTimeInterval(3600)))
    }
}
