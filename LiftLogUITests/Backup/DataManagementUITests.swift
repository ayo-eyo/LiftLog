import XCTest

/// FR-1 of plans/features/backup-sync: the gear in the workout list opens «Данные», the
/// summary reflects the store, and exporting JSON brings up the share sheet. What happens
/// inside the system sheet isn't ours to automate; the file contents are covered by
/// `BackupTests`.
final class DataManagementUITests: XCTestCase {
    @MainActor
    func test_экранДанныхПоказываетСводкуИОткрываетШторкуЭкспорта() throws {
        let app = AppLauncher.launch()

        let dataButton = app.buttons["workoutList.data"]
        dataButton.waitUntilVisible()
        dataButton.tap()

        let workoutsRow = app.descendants(matching: .any)["dataManagement.summary.workouts"]
        XCTAssertTrue(workoutsRow.waitForExistence(timeout: 5), "Экран «Данные» должен показать сводку")
        XCTAssertTrue(workoutsRow.label.contains("0"), "В пустом приложении тренировок нет; строка показала «\(workoutsRow.label)»")

        app.buttons["dataManagement.exportJSON"].tap()

        // Our identifier on the controller's view, or the system's own list identifier —
        // whichever the running iOS exposes.
        let deadline = Date().addingTimeInterval(8)
        var shareSheetShown = false
        while Date() < deadline {
            if app.descendants(matching: .any)["dataManagement.shareSheet"].exists || app.otherElements["ActivityListView"].exists {
                shareSheetShown = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(shareSheetShown, "Выгрузка JSON должна открыть системную шторку «Поделиться»")
    }
}
