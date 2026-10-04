import XCTest
@testable import WEEKNOTE

final class WebsiteMigrationTests: XCTestCase {
    private let originalUUID = UUID(uuidString: "54B91E74-046F-4A0E-9C60-38998410DE40")!

    private func websiteObject() -> [String: Any] {
        [
            "lists": [["id": "work", "name": "仕事", "icon": "folder"]],
            "habits": [["id": "reading", "name": "読書", "icon": "book", "goal": 30, "unit": "分"]],
            "tasks": [
                ["id": originalUUID.uuidString, "title": "資料", "notes": "メモ", "listId": "work", "date": "2026-10-03", "time": "", "kind": "todo", "done": true, "completedAt": "2026-10-03T11:15:23.123+09:00", "priority": true, "repeat": false, "location": ""],
                ["id": "legacy-event", "title": "会議", "notes": "", "listId": "work", "date": "2026-10-04", "time": "09:30", "kind": "event", "done": true, "completedAt": "2026-10-04", "priority": false, "repeat": false, "location": "会議室"],
                ["id": "undated-repeat", "title": "日報", "notes": "", "listId": "work", "date": "", "time": "", "kind": "todo", "done": false, "completedAt": "", "priority": false, "repeat": true, "location": ""]
            ],
            "logs": [["id": "log-1", "habitId": "reading", "date": "2026-10-03", "amount": 15]],
            "bookmarks": [["id": "link-1", "title": "参考", "url": "https://example.com", "listId": "work", "notes": "保存したメモ"]]
        ]
    }

    private func bytes(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
    private func reference() throws -> Date { try XCTUnwrap(CalendarSupport.date(fromDayKey: "2026-10-04")).addingTimeInterval(12 * 3600) }
    private func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("WEEKNOTE-migration-\(UUID())", isDirectory: true).appendingPathComponent("planner.json")
    }

    @MainActor
    func testWebsiteImportPreservesReferencesDatesAndActualTimestamp() async throws {
        let path = file(); defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let now = try reference()
        let store = PlannerStore(data: .empty, fileURL: path, now: { now })
        try store.importJSON(bytes(websiteObject()))
        XCTAssertEqual(store.data.tasks.count, 3)
        XCTAssertEqual(store.data.lists.count, 2)
        XCTAssertEqual(store.data.habits.count, 1)
        let work = try XCTUnwrap(store.data.lists.first { $0.name == "仕事" })
        XCTAssertTrue(store.data.tasks.allSatisfy { $0.listID == work.id })
        XCTAssertEqual(store.data.links[0].listID, work.id)
        XCTAssertEqual(store.data.logs[0].habitID, store.data.habits[0].id)
        XCTAssertEqual(CalendarSupport.dayKey(store.data.logs[0].date), "2026-10-03")
        XCTAssertEqual(store.data.logs[0].minutes, 15)
        XCTAssertEqual(store.data.links[0].notes, "保存したメモ")
        let original = try XCTUnwrap(store.data.tasks.first { $0.title == "資料" })
        XCTAssertEqual(original.id, originalUUID)
        XCTAssertFalse(original.completionDateOnly)
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(original.completedAt, formatter.date(from: "2026-10-03T11:15:23.123+09:00"))
        XCTAssertEqual(CalendarSupport.dayKey(try XCTUnwrap(original.date)), "2026-10-03")
    }

    @MainActor
    func testDateOnlyLegacyCompletionDoesNotInventTimeOrClaimOnTime() async throws {
        let path = file(); defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let now = try reference()
        let store = PlannerStore(data: .empty, fileURL: path, now: { now })
        try store.importJSON(bytes(websiteObject()))
        let event = try XCTUnwrap(store.data.tasks.first { $0.kind == .event })
        XCTAssertEqual(CalendarSupport.dayKey(try XCTUnwrap(event.completedAt)), "2026-10-04")
        XCTAssertEqual(CalendarSupport.calendar.component(.hour, from: event.date!), 9)
        XCTAssertEqual(CalendarSupport.calendar.component(.minute, from: event.date!), 30)
        XCTAssertTrue(event.completionDateOnly)
        XCTAssertEqual(event.completionStatus, .unknown)
        XCTAssertTrue(store.toggleTask(event))
        XCTAssertTrue(store.toggleTask(event))
        let actual = try XCTUnwrap(store.data.tasks.first { $0.id == event.id })
        XCTAssertEqual(actual.completedAt, now)
        XCTAssertFalse(actual.completionDateOnly)
        XCTAssertEqual(actual.completionStatus, .late)
    }

    @MainActor
    func testNonUUIDIdentifiersRemainStableAcrossRepeatedImports() async throws {
        let path = file(); defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let now = try reference()
        let store = PlannerStore(data: .empty, fileURL: path, now: { now })
        let backup = try bytes(websiteObject())
        try store.importJSON(backup)
        let first = store.data
        try store.importJSON(backup)
        XCTAssertEqual(store.data, first)
        let nativeBackup = try store.exportJSON()
        try store.importJSON(nativeBackup)
        XCTAssertEqual(store.data, first)
        let repeatTask = try XCTUnwrap(store.data.tasks.first { $0.repeatsDaily })
        XCTAssertNil(repeatTask.date)
        XCTAssertTrue(store.toggleTask(repeatTask))
        let tomorrow = try XCTUnwrap(store.data.tasks.first { $0.seriesID == repeatTask.seriesID && $0.id != repeatTask.id })
        XCTAssertEqual(CalendarSupport.dayKey(try XCTUnwrap(tomorrow.date)), "2026-10-05")
    }

    @MainActor
    func testOrphanReferenceDuplicateIDsAndInvalidDatesRejectWholeImport() async throws {
        let path = file(); defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let now = try reference()
        let store = PlannerStore(data: .empty, fileURL: path, now: { now })
        let original = store.data
        let disk = try Data(contentsOf: path)
        var object = websiteObject()
        var tasks = try XCTUnwrap(object["tasks"] as? [[String: Any]])
        tasks[0]["listId"] = "missing-list"; object["tasks"] = tasks
        XCTAssertThrowsError(try store.importJSON(bytes(object)))
        object = websiteObject()
        object["logs"] = [["id": "log-1", "habitId": "missing-habit", "date": "2026-10-03", "amount": 15]]
        XCTAssertThrowsError(try store.importJSON(bytes(object)))
        object = websiteObject()
        tasks = try XCTUnwrap(object["tasks"] as? [[String: Any]])
        tasks.append(tasks[0]); object["tasks"] = tasks
        XCTAssertThrowsError(try store.importJSON(bytes(object)))
        object = websiteObject()
        tasks = try XCTUnwrap(object["tasks"] as? [[String: Any]])
        tasks[0]["date"] = "2026-02-30"; object["tasks"] = tasks
        XCTAssertThrowsError(try store.importJSON(bytes(object)))
        XCTAssertEqual(store.data, original)
        XCTAssertEqual(try Data(contentsOf: path), disk)
    }

    @MainActor
    func testNonMinuteHabitUnitFailsWithExplicitReason() async throws {
        let path = file(); defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let now = try reference()
        let store = PlannerStore(data: .empty, fileURL: path, now: { now })
        var object = websiteObject()
        object["habits"] = [["id": "reading", "name": "読書", "icon": "book", "goal": 30, "unit": "ページ"]]
        XCTAssertThrowsError(try store.importJSON(bytes(object))) { error in
            XCTAssertTrue(error.localizedDescription.contains("読書"))
            XCTAssertTrue(error.localizedDescription.contains("ページ"))
            XCTAssertTrue(error.localizedDescription.contains("変換できません"))
        }
        XCTAssertTrue(store.data.tasks.isEmpty)
        XCTAssertTrue(store.data.habits.isEmpty)
    }

    @MainActor
    func testNativeSchemaIsNeverReinterpretedAsWebsiteOnFailure() async throws {
        let path = file(); defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let now = try reference()
        let store = PlannerStore(data: .empty, fileURL: path, now: { now })
        var object = websiteObject()
        object["schemaVersion"] = 1
        object["links"] = []
        object["isSample"] = false
        XCTAssertThrowsError(try store.importJSON(bytes(object)))
        XCTAssertTrue(store.data.tasks.isEmpty)
        XCTAssertFalse(store.saveTask(PlannerTask(title: "範囲外の日付", date: Date(timeIntervalSince1970: 1e100))))
        XCTAssertTrue(store.data.tasks.isEmpty)
    }
}
