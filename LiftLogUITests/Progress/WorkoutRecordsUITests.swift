import XCTest

/// FR-3 of plans/features/progress-analytics in one pass: a second workout of the same
/// exercise shows «Прошлый раз», a heavier set raises the record banner, and the finished
/// workout lists the record. Unit suites cover the branches (`ExerciseRecordBeatenTests`,
/// `WorkoutRecordsSummaryTests`).
final class WorkoutRecordsUITests: XCTestCase {
    private let exerciseName = "Barbell Bench Press - Medium Grip"

    @MainActor
    func test_прошлыйРазБаннерРекордаИСводкаРекордов() throws {
        let app = AppLauncher.launch()

        // First workout: the plan's default 20 kg × 10 — nothing to beat yet.
        startWorkout(app)
        openExercise(app)
        logSet(app)
        XCTAssertFalse(app.descendants(matching: .any)["exerciseLog.recordBanner"].exists, "Первый подход в истории не рекорд")
        finishWorkout(app)

        // Second workout: last time is shown, and one weight step up is a record.
        startWorkout(app)
        openExercise(app)

        let lastTime = app.descendants(matching: .any)["exerciseLog.lastTime"]
        XCTAssertTrue(lastTime.waitForExistence(timeout: 5), "Во второй тренировке должна быть строка «Прошлый раз»")
        XCTAssertTrue(lastTime.label.contains("20×10"), "«Прошлый раз» должен показать подход первой тренировки; показано «\(lastTime.label)»")

        // Weight stepper: step 0.25 (`WeightInputRow`) → 20,25 кг.
        app.buttons.matching(identifier: "Increment").element(boundBy: 0).tap()
        logSet(app)

        let banner = app.descendants(matching: .any)["exerciseLog.recordBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 2), "Более тяжёлый подход должен показать баннер рекорда")
        XCTAssertTrue(banner.label.contains("20,25"), "Баннер должен назвать новый рекорд; показано «\(banner.label)»")

        finishWorkout(app)

        app.cells.firstMatch.waitUntilVisible()
        app.cells.firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["workoutDetail.records"].waitForExistence(timeout: 5),
            "Завершённая тренировка с рекордом должна показать сводку рекордов"
        )
    }

    private func startWorkout(_ app: XCUIApplication) {
        let addWorkout = app.buttons["workoutList.addWorkout"]
        addWorkout.waitUntilVisible()
        addWorkout.tap()

        let addExerciseButton = app.buttons["Добавить упражнение"]
        addExerciseButton.waitUntilVisible()
        addExerciseButton.tap()

        let searchField = app.searchFields["Поиск упражнения"]
        searchField.waitUntilVisible()
        searchField.tap()
        searchField.typeText(exerciseName)

        let exerciseRow = app.buttons[exerciseName]
        exerciseRow.waitUntilVisible()
        exerciseRow.tap()

        let addPlannedSetButton = app.buttons["Добавить подход"]
        addPlannedSetButton.waitUntilVisible()
        addPlannedSetButton.tap()

        let doneButton = app.buttons["Готово"]
        doneButton.waitUntilVisible()
        doneButton.tap()

        let startButton = app.buttons["Начать"]
        startButton.waitUntilVisible()
        startButton.tap()
    }

    private func openExercise(_ app: XCUIApplication) {
        let link = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", exerciseName)).firstMatch
        link.waitUntilVisible()
        link.tap()
    }

    /// Same polling as `WorkoutAutoAdvanceUITests.logSet`: the button stays disabled until
    /// the prefill from `.task(id:)` lands.
    private func logSet(_ app: XCUIApplication) {
        let button = app.buttons["exerciseLog.addSet"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        let deadline = Date().addingTimeInterval(5)
        while !button.isEnabled, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        button.tap()
    }

    private func finishWorkout(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let finishButton = app.buttons["Завершить"]
        finishButton.waitUntilVisible()
        finishButton.tap()
    }
}
