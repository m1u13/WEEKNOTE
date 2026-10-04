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
        let running = element("symbol.figure.run")
        XCTAssertTrue(running.waitForExistence(timeout: 5))
        reveal(running, in: "editor.habit")
        running.tap()
        let name = element("habit.name")
        waitUntil("Choosing an icon should update the preview, close the keyboard, and return to the name") {
            self.element("editor.selectedSymbolName").label == "ランニング"
                && !self.app.keyboards.firstMatch.exists && name.isHittable
        }
        XCTAssertTrue(element("editor.selectedSymbol").isHittable)
        capture("habit-icon-search")

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
        month.swipeLeft()
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

    func testDateRibbonScrollsHorizontally() throws {
        let ribbon = element("date.ribbon")
        XCTAssertTrue(ribbon.waitForExistence(timeout: 5))
        let initialDates = visibleDateElements(in: ribbon)
        XCTAssertGreaterThan(initialDates.count, 2)
        let firstDate = try XCTUnwrap(initialDates.first)
        let initialX = firstDate.frame.minX
        capture("dates-before-scroll")
        ribbon.swipeLeft()
        waitUntil("Horizontal scrolling should reveal different dates") {
            // A single frame query stays within the polling timeout. Enumerating
            // every offscreen date can take longer than the entire expectation.
            abs(firstDate.frame.minX - initialX) > 20
        }
        capture("dates-after-scroll")
        let visibleDate = try XCTUnwrap(visibleDateElements(in: ribbon).first)
        let dateLabel = visibleDate.label
        visibleDate.tap()
        // Choosing a distant day replaces the ribbon's date range. Resolve the
        // same day by its label rather than retaining its former array index.
        waitUntil("Selecting a date should update its selected state") { ribbon.buttons[dateLabel].isSelected }
        capture("date-selected")
    }

    func testHabitContextMenuEditAndCancelledDeletion() {
        let habit = element("habit.読書")
        XCTAssertTrue(habit.waitForExistence(timeout: 5))
        habit.press(forDuration: 1)
        capture("habit-context-menu")
        tapMenuAction("編集")
        let editor = element("editor.habit")
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(element("habit.name").value as? String, "読書")
        assertFitsScreen(editor)
        capture("habit-context-edit")
        app.buttons["キャンセル"].tap()
        waitUntil("Cancelling the editor should return to the habit") { !editor.exists && habit.isHittable }

        habit.press(forDuration: 1)
        tapMenuAction("削除")
        let confirmation = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "読書", "すべての記録")).firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        capture("habit-delete-confirmation")
        app.buttons["キャンセル"].tap()
        waitUntil("Cancelling deletion should retain the habit") { !confirmation.exists && habit.isHittable }
        habit.tap()
        XCTAssertTrue(element("habit.detail").waitForExistence(timeout: 5))
        XCTAssertTrue(element("habit.chart").exists)
        capture("habit-retained-after-cancel")
    }

    func testListContextMenuIconPreviewAndKeyboardDismissal() {
        openTab("リスト")
        let list = element("list.item.仕事")
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        list.press(forDuration: 1)
        capture("list-context-menu")
        tapMenuAction("編集")
        let editor = element("editor.list")
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        assertFitsScreen(editor)
        XCTAssertEqual(element("list.name").value as? String, "仕事")
        let search = element("symbol.search")
        reveal(search, in: "editor.list")
        XCTAssertTrue(search.isHittable)
        search.tap()
        search.typeText("ランニング")
        let icon = element("symbol.figure.run")
        XCTAssertTrue(icon.waitForExistence(timeout: 5))
        reveal(icon, in: "editor.list")
        icon.tap()
        let name = element("list.name")
        waitUntil("The list icon preview and name should be visible with the keyboard closed") {
            self.element("editor.selectedSymbolName").label == "ランニング"
                && !self.app.keyboards.firstMatch.exists && name.isHittable
        }
        XCTAssertTrue(element("editor.selectedSymbol").isHittable)
        capture("list-icon-preview")
        element("editor.save").tap()
        waitUntil("Saving the list should close the editor") { !editor.exists }
        list.press(forDuration: 1)
        tapMenuAction("編集")
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(element("editor.selectedSymbolName").label, "ランニング")
        capture("list-icon-saved")
    }

    func testCalendarSwipesMonthsWithoutBlockingVerticalScrolling() {
        openTab("カレンダー")
        let month = element("calendar.month")
        let title = element("calendar.monthTitle")
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        let initialTitle = title.label
        month.swipeLeft()
        waitUntil("A left swipe should show the next month") { title.label != initialTitle }
        capture("calendar-swipe-next")
        month.swipeRight()
        waitUntil("A right swipe should return to the original month") { title.label == initialTitle }
        capture("calendar-swipe-back")
        let initialY = title.frame.minY
        month.swipeUp()
        waitUntil("Vertical dragging on the calendar should scroll its enclosing screen") { title.frame.minY < initialY - 20 }
        XCTAssertEqual(title.label, initialTitle, "Vertical scrolling must retain the displayed month")
        capture("calendar-vertical-scroll")
    }

    func testHabitChartSwipesEachPeriodAndSelectsHistoryDay() {
        element("habit.読書").tap()
        let detail = element("habit.detail")
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        let picker = element("habit.period")
        let label = element("habit.period.label")
        for period in ["Week", "Month", "Year"] {
            picker.buttons[period].tap()
            let initialLabel = label.label
            let chart = element("habit.chart")
            XCTAssertTrue(chart.waitForExistence(timeout: 5))
            chart.swipeLeft()
            waitUntil("A left chart swipe should change the \(period) period") { label.label != initialLabel }
            capture("habit-chart-\(period.lowercased())-next")
            element("habit.chart").swipeRight()
            waitUntil("A right chart swipe should restore the \(period) period") { label.label == initialLabel }
        }
        let initialPeriod = label.label
        let initialY = label.frame.minY
        element("habit.chart").swipeUp()
        waitUntil("Vertical chart dragging should scroll the detail") { label.frame.minY < initialY - 20 }
        XCTAssertEqual(label.label, initialPeriod, "Vertical dragging must retain the chart period")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let today = element("habit.history.day." + formatter.string(from: Date()))
        reveal(today, in: "habit.detail")
        XCTAssertTrue(today.isHittable)
        today.tap()
        waitUntil("Selecting a history day should mark that day selected") { today.isSelected }
        XCTAssertFalse(app.staticTexts["日付をタップして記録を確認"].exists)
        capture("habit-history-selected")
    }

    func testHeaderDeadlineSettingPersistsAcrossLaunch() {
        let initialHeading = element("week.heading").label
        element("header.configure").tap()
        let settings = element("header.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        let deadline = element("header.mode.deadline")
        XCTAssertTrue(deadline.waitForExistence(timeout: 5))
        deadline.tap()
        let title = element("header.deadline.title")
        reveal(title, in: "header.settings")
        XCTAssertTrue(title.isHittable)
        title.tap()
        let previousTitle = title.value as? String ?? ""
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previousTitle.count) + "UI goal")
        let date = element("header.deadline.date")
        reveal(date, in: "header.settings")
        XCTAssertTrue(date.exists)
        let savedDate = date.value as? String
        capture("header-deadline-settings")
        element("header.save").tap()
        waitUntil("Saving the deadline should replace the week number") { self.element("week.heading").label != initialHeading }
        XCTAssertTrue(app.staticTexts["UI goal当日"].waitForExistence(timeout: 5))
        capture("header-deadline-saved")

        app.terminate()
        app.launchArguments = ["--uitesting", "--preserve-header"]
        app.launch()
        XCTAssertTrue(app.staticTexts["UI goal当日"].waitForExistence(timeout: 10))
        XCTAssertEqual(element("week.heading").label, "0")
        element("header.configure").tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "UI goal")
        if let savedDate { XCTAssertEqual(date.value as? String, savedDate) }
        capture("header-deadline-restored")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func openTab(_ name: String) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    private func tapMenuAction(_ title: String) {
        let action = app.buttons[title].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.tap()
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
                let viewport = container.exists ? screen.intersection(container.frame) : screen
                let top = max(screen.minY + 100, viewport.minY + 70)
                var bottom = min(screen.maxY - 130, viewport.maxY - 24)
                if keyboard.exists { bottom = min(bottom, keyboard.frame.minY - 25) }
                if identifier == "screen.week" {
                    let addButton = element("task.add")
                    if addButton.exists { bottom = min(bottom, addButton.frame.minY - 24) }
                }
                guard bottom - top > 50 else { return }
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let x = viewport.midX + viewport.width * 0.35
                let upper = origin.withOffset(CGVector(dx: x, dy: top))
                let lower = origin.withOffset(CGVector(dx: x, dy: bottom))
                if direction { lower.press(forDuration: 0.05, thenDragTo: upper) }
                else { upper.press(forDuration: 0.05, thenDragTo: lower) }
            }
        }
    }
}
