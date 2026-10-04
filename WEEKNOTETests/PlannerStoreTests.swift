import XCTest
@testable import WEEKNOTE

final class PlannerStoreTests: XCTestCase {
    private struct Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WEEKNOTE-tests-\(UUID())", isDirectory: true)
        var file: URL { directory.appendingPathComponent("planner.json") }
        func cleanup() { try? FileManager.default.removeItem(at: directory) }
    }

    private func day(_ key: String) throws -> Date { try XCTUnwrap(CalendarSupport.date(fromDayKey: key)) }

    @MainActor
    func testCompletionTimestampAndUncompletePersistAcrossRelaunch() async throws {
        let fixture = Fixture(); defer { fixture.cleanup() }
        let current = try day("2026-10-04").addingTimeInterval(12 * 3600)
        let store = PlannerStore(data: .empty, fileURL: fixture.file, now: { current })
        let task = PlannerTask(title: "確認", date: current.addingTimeInterval(-3600), kind: .event)
        XCTAssertTrue(store.saveTask(task))
        XCTAssertTrue(store.toggleTask(task))
        let loaded = PlannerStore(fileURL: fixture.file, now: { current })
        XCTAssertEqual(loaded.data.tasks.count, 1)
        XCTAssertEqual(loaded.data.tasks[0].completedAt, current)
        XCTAssertEqual(loaded.data.tasks[0].completionStatus, .late)
        XCTAssertTrue(loaded.toggleTask(task))
        XCTAssertFalse(loaded.data.tasks[0].isCompleted)
        XCTAssertNil(loaded.data.tasks[0].completedAt)
        XCTAssertEqual(PlannerStore(fileURL: fixture.file, now: { current }).data, loaded.data)
    }

    @MainActor
    func testDailyRecurrenceCrossesYearAndDoesNotDuplicateAfterUndo() async throws {
        let fixture = Fixture(); defer { fixture.cleanup() }
        let current = try day("2026-12-31").addingTimeInterval(16 * 3600 + 45 * 60)
        let store = PlannerStore(data: .empty, fileURL: fixture.file, now: { current })
        let task = PlannerTask(title: "日報", date: current, kind: .event, repeatsDaily: true)
        XCTAssertTrue(store.saveTask(task))
        XCTAssertTrue(store.toggleTask(task))
        let next = try XCTUnwrap(store.data.tasks.first { $0.id != task.id })
        XCTAssertEqual(CalendarSupport.dayKey(try XCTUnwrap(next.date)), "2027-01-01")
        XCTAssertEqual(CalendarSupport.calendar.component(.hour, from: next.date!), 16)
        XCTAssertEqual(CalendarSupport.calendar.component(.minute, from: next.date!), 45)
        XCTAssertEqual(next.seriesID, task.id)
        XCTAssertFalse(next.isCompleted)
        XCTAssertNil(next.completedAt)
        XCTAssertTrue(store.toggleTask(task))
        XCTAssertTrue(store.toggleTask(task))
        XCTAssertEqual(store.data.tasks.count, 2)
    }

    @MainActor
    func testCompletingOldDailyOccurrenceSchedulesTomorrowRatherThanBackfilling() async throws {
        let fixture = Fixture(); defer { fixture.cleanup() }
        let current = try day("2026-10-04").addingTimeInterval(20 * 3600)
        let store = PlannerStore(data: .empty, fileURL: fixture.file, now: { current })
        let task = PlannerTask(title: "確認", date: try day("2026-09-30").addingTimeInterval(9 * 3600), repeatsDaily: true)
        XCTAssertTrue(store.saveTask(task)); XCTAssertTrue(store.toggleTask(task))
        let next = try XCTUnwrap(store.data.tasks.first { $0.id != task.id })
        XCTAssertEqual(CalendarSupport.dayKey(try XCTUnwrap(next.date)), "2026-10-05")
        XCTAssertEqual(CalendarSupport.calendar.component(.hour, from: next.date!), 9)
    }

    @MainActor
    func testDeletingListMovesTasksAndLinksToInboxWithoutLoss() async throws {
        let fixture = Fixture(); defer { fixture.cleanup() }
        let store = PlannerStore(data: .empty, fileURL: fixture.file)
        let list = PlannerList(name: "仕事")
        XCTAssertTrue(store.saveList(list))
        let task = PlannerTask(title: "資料", listID: list.id)
        let link = SavedLink(title: "参考", url: "https://example.com/reference", listID: list.id)
        XCTAssertTrue(store.saveTask(task)); XCTAssertTrue(store.saveLink(link))
        XCTAssertTrue(store.deleteList(list))
        XCTAssertEqual(store.data.tasks.first?.id, task.id)
        XCTAssertEqual(store.data.tasks.first?.listID, PlannerList.inboxID)
        XCTAssertEqual(store.data.links.first?.listID, PlannerList.inboxID)
        XCTAssertFalse(store.deleteList(PlannerList.inbox))
    }

    @MainActor
    func testFutureHabitLogsAreRejectedAndDeletingHabitRemovesItsLogs() async throws {
        let fixture = Fixture(); defer { fixture.cleanup() }
        let current = try day("2026-10-04")
        let store = PlannerStore(data: .empty, fileURL: fixture.file, now: { current })
        let habit = Habit(name: "読書", goalMinutes: 30)
        XCTAssertTrue(store.saveHabit(habit))
        XCTAssertFalse(store.addHabitLog(habitID: habit.id, date: CalendarSupport.addingDays(1, to: current), minutes: 5))
        XCTAssertTrue(store.data.logs.isEmpty)
        XCTAssertFalse(store.addHabitLog(habitID: habit.id, date: current, minutes: -2))
        XCTAssertTrue(store.addHabitLog(habitID: habit.id, date: current, minutes: 15))
        XCTAssertTrue(store.addHabitLog(habitID: habit.id, date: current, minutes: 20))
        XCTAssertEqual(store.habitMinutes(habit, on: current), 35)
        XCTAssertTrue(store.deleteHabit(habit))
        XCTAssertTrue(store.data.logs.isEmpty)
    }

    @MainActor
    func testValidBackupRoundTripsAndInvalidImportLeavesMemoryAndDiskIntact() async throws {
        let fixture = Fixture(); defer { fixture.cleanup() }
        let current = try day("2026-10-04")
        let store = PlannerStore(data: .empty, fileURL: fixture.file, now: { current })
        XCTAssertTrue(store.saveTask(PlannerTask(title: "保持する", date: current)))
        let original = store.data
        let disk = try Data(contentsOf: fixture.file)
        let bytes = try store.exportJSON()
        try store.importJSON(bytes)
        XCTAssertEqual(store.data, original)
        var invalid = original
        invalid.tasks[0].listID = UUID()
        XCTAssertThrowsError(try store.importJSON(PlannerStore.encoder().encode(invalid)))
        XCTAssertEqual(store.data, original)
        XCTAssertEqual(try Data(contentsOf: fixture.file), disk)
        invalid = original
        invalid.schemaVersion = 99
        XCTAssertThrowsError(try store.importJSON(PlannerStore.encoder().encode(invalid)))
        XCTAssertEqual(store.data, original)
        XCTAssertThrowsError(try store.importJSON(Data("not JSON".utf8)))
    }

    @MainActor
    func testDuplicateIdentifiersAndUnsafeLinksAreRejectedOnImport() async throws {
        let fixture = Fixture(); defer { fixture.cleanup() }
        let store = PlannerStore(data: .empty, fileURL: fixture.file)
        let task = PlannerTask(title: "重複")
        let duplicate = PlannerData(tasks: [task, task])
        XCTAssertThrowsError(try store.importJSON(PlannerStore.encoder().encode(duplicate)))
        XCTAssertTrue(store.data.tasks.isEmpty)
        XCTAssertFalse(store.saveLink(SavedLink(title: "不可", url: "javascript:alert(1)")))
        XCTAssertFalse(store.saveLink(SavedLink(title: "不可", url: "file:///etc/passwd")))
        XCTAssertTrue(store.data.links.isEmpty)
    }

    @MainActor
    func testUnreadableFileIsPreservedUntilExplicitRecovery() async throws {
        let fixture = Fixture(); defer { fixture.cleanup() }
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
        let corrupt = Data("{broken backup".utf8)
        try corrupt.write(to: fixture.file)
        let store = PlannerStore(fileURL: fixture.file)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.saveTask(PlannerTask(title: "保存停止")))
        XCTAssertEqual(try Data(contentsOf: fixture.file), corrupt)
        XCTAssertTrue(store.reset())
        XCTAssertTrue(store.data.tasks.isEmpty)
        let copies = try FileManager.default.contentsOfDirectory(at: fixture.directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("planner-unreadable-") }
        XCTAssertEqual(copies.count, 1)
        XCTAssertEqual(try Data(contentsOf: copies[0]), corrupt)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testFailedDiskWriteDoesNotPublishUnpersistedMutation() async throws {
        let fixture = Fixture(); defer { fixture.cleanup() }
        let store = PlannerStore(data: .empty, fileURL: fixture.file)
        let original = store.data
        try FileManager.default.removeItem(at: fixture.directory)
        try Data("directory is a file".utf8).write(to: fixture.directory)
        XCTAssertFalse(store.saveTask(PlannerTask(title: "失敗")))
        XCTAssertEqual(store.data, original)
        XCTAssertNotNil(store.errorMessage)
    }
}
