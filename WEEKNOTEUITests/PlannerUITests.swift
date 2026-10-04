import XCTest

final class PlannerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(element("week.heading").waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    func testTaskEditorFitsScreenAndTaskCanBeCompleted() {
        capture("week-light")
        element("task.add").tap()
        let editor = element("editor.task")
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        assertFitsScreen(editor)
        let title = element("task.title")
        XCTAssertTrue(title.exists)
        assertFitsScreen(title, minimumWidth: 100)
        capture("task-editor")

        let taskName = "UI test task"
        title.tap()
        title.typeText(taskName)
        assertFitsScreen(title, minimumWidth: 100)
        capture("task-editor-keyboard")
        element("editor.save").tap()
        waitUntil("Task editor should close after saving") { !editor.exists }

        let completion = app.buttons[taskName + "を完了にする"]
        reveal(completion, in: "screen.week")
        XCTAssertTrue(completion.isHittable)
        completion.tap()
        XCTAssertTrue(app.buttons[taskName + "を未完了に戻す"].waitForExistence(timeout: 5))
        capture("task-completed")
    }

    func testHabitIconSearchAndCreation() {
        element("habit.add").tap()
        let editor = element("editor.habit")
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        assertFitsScreen(editor)
        capture("habit-editor")

        let search = element("symbol.search")
        reveal(search, in: "editor.habit")
        XCTAssertTrue(search.isHittable)
        search.tap()
        search.typeText("ランニング")
        let running = app.buttons["ランニング"]
        XCTAssertTrue(running.waitForExistence(timeout: 5))
        reveal(running, in: "editor.habit")
        running.tap()
        waitUntil("The chosen habit icon should be selected") { running.isSelected }
        capture("habit-icon-search")

        let name = element("habit.name")
        reveal(name, in: "editor.habit")
        XCTAssertTrue(name.isHittable)
        name.tap()
        name.typeText("UI test habit")
        element("editor.save").tap()
        waitUntil("Habit editor should close after saving") { !editor.exists }
        XCTAssertTrue(element("habit.UI test habit").waitForExistence(timeout: 5))
        capture("habit-created")
    }

    func testHabitDetailFitsScreenAndContainsChart() {
        element("habit.読書").tap()
        let detail = element("habit.detail")
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        assertFitsScreen(detail)
        XCTAssertTrue(element("habit.chart").waitForExistence(timeout: 5))
        capture("habit-detail-light")
        app.buttons["閉じる"].tap()
        waitUntil("Habit detail should close") { !detail.exists }
    }

    func testDarkAppearanceAndHabitDetail() {
        openTab("設定")
        let picker = element("appearance.picker")
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let dark = picker.buttons["ダーク"]
        XCTAssertTrue(dark.exists)
        dark.tap()
        waitUntil("Dark appearance should be selected") { dark.isSelected }
        capture("settings-dark")
        openTab("今週")
        capture("week-dark")
        element("habit.読書").tap()
        let detail = element("habit.detail")
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        assertFitsScreen(detail)
        capture("habit-detail-dark")
        app.buttons["閉じる"].tap()
        openTab("設定")
        picker.buttons["ライト"].tap()
        waitUntil("Light appearance should be selected") { picker.buttons["ライト"].isSelected }
        capture("settings-light")
    }

    func testCalendarNavigationAndEventCompletion() {
        openTab("カレンダー")
        let month = element("calendar.month")
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        assertFitsScreen(month)
        XCTAssertGreaterThan(month.descendants(matching: .button).count, 20)
        capture("calendar")
        let firstDate = month.descendants(matching: .button).firstMatch.label
        app.buttons["次の月"].tap()
        waitUntil("Next month should display different calendar dates") {
            month.descendants(matching: .button).firstMatch.label != firstDate
        }
        capture("calendar-next-month")
        app.buttons["今日"].tap()

        element("event.add").tap()
        let editor = element("editor.task")
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        assertFitsScreen(editor)
        let eventName = "UI test event"
        let title = element("task.title")
        title.tap()
        title.typeText(eventName)
        capture("event-editor")
        element("editor.save").tap()
        waitUntil("Event editor should close after saving") { !editor.exists }
        let completion = app.buttons[eventName + "を完了にする"]
        reveal(completion, in: "calendar.month")
        XCTAssertTrue(completion.isHittable)
        completion.tap()
        XCTAssertTrue(app.buttons[eventName + "を未完了に戻す"].waitForExistence(timeout: 5))
        let completedEvent = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", eventName, "時間内に完了")).firstMatch
        XCTAssertTrue(completedEvent.waitForExistence(timeout: 5))
        capture("event-completed")
    }

    func testDateRibbonScrollsHorizontally() {
        let ribbon = element("date.ribbon")
        XCTAssertTrue(ribbon.waitForExistence(timeout: 5))
        let initialDates = visibleDateLabels(in: ribbon)
        XCTAssertGreaterThan(initialDates.count, 2)
        capture("dates-before-scroll")
        ribbon.swipeLeft()
        waitUntil("Horizontal scrolling should reveal different dates") {
            self.visibleDateLabels(in: ribbon) != initialDates
        }
        capture("dates-after-scroll")
        let visibleDate = visibleDateElements(in: ribbon).first
        XCTAssertNotNil(visibleDate)
        visibleDate?.tap()
        waitUntil("Selecting a date should update its selected state") { visibleDate?.isSelected == true }
        capture("date-selected")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func openTab(_ name: String) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertFitsScreen(_ view: XCUIElement, minimumWidth: CGFloat? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let screen = app.windows.firstMatch.frame
        let frame = view.frame
        XCTAssertGreaterThan(frame.height, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minX, screen.minX - 2, "View extends beyond the left side of the screen", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, screen.maxX + 2, "View extends beyond the right side of the screen", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.width + 2, minimumWidth ?? screen.width - 48, "Native sheet content is unexpectedly narrow", file: file, line: line)
    }

    private func visibleDateLabels(in ribbon: XCUIElement) -> [String] {
        visibleDateElements(in: ribbon).map(\.label)
    }

    private func visibleDateElements(in ribbon: XCUIElement) -> [XCUIElement] {
        let viewport = ribbon.frame.insetBy(dx: 2, dy: 0)
        return ribbon.descendants(matching: .button).allElementsBoundByIndex
            .filter {
                let frame = $0.frame
                // CoreSimulator cannot calculate hit points for distant, clipped dates.
                // Check the physical viewport before asking XCTest about hittability.
                return frame.width > 0 && frame.height > 0
                    && viewport.contains(frame)
                    && $0.isHittable
            }
    }

    private func waitUntil(_ message: String, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line, condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, message, file: file, line: line)
    }

    private func reveal(_ target: XCUIElement, in identifier: String) {
        let screen = app.windows.firstMatch.frame
        let container = element(identifier)
        for direction in [true, false] {
            for _ in 0..<6 {
                if target.exists && target.isHittable { return }
                let keyboard = app.keyboards.firstMatch
                let top = max(screen.minY + 100, container.exists ? container.frame.minY + 70 : screen.minY + 100)
                let bottom = min(screen.maxY - 130, keyboard.exists ? keyboard.frame.minY - 25 : screen.maxY - 130)
                guard bottom - top > 50 else { return }
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let upper = origin.withOffset(CGVector(dx: screen.width * 0.9, dy: top))
                let lower = origin.withOffset(CGVector(dx: screen.width * 0.9, dy: bottom))
                if direction { lower.press(forDuration: 0.05, thenDragTo: upper) }
                else { upper.press(forDuration: 0.05, thenDragTo: lower) }
            }
        }
    }
}
