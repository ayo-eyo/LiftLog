import XCTest

/// FR-5 of plans/features/progress-analytics: the Analytics tab starts on its empty state
/// and, once a workout is finished, shows the period summary and the muscle map. The
/// numbers behind it are covered by `TrainingAnalyticsTests`.
final class AnalyticsUITests: XCTestCase {
    private let exerciseName = "Barbell Bench Press - Medium Grip"

    @MainActor
    func test_аналитикаПустаДоПервойТренировкиИПоказываетСводкуПосле() throws {
        let app = AppLauncher.launch()

        app.tabBars.buttons["Аналитика"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["analytics.empty"].waitForExistence(timeout: 5),
            "Без завершённых тренировок вкладка должна показать пустое состояние"
        )

        app.tabBars.buttons["Тренировки"].tap()
        finishWorkoutWithOneSet(app)

        app.tabBars.buttons["Аналитика"].tap()
        let workoutsTile = app.descendants(matching: .any)["analytics.summary.workouts"]
        XCTAssertTrue(workoutsTile.waitForExistence(timeout: 5), "После завершения тренировки должна появиться сводка")
        XCTAssertTrue(workoutsTile.label.contains("1"), "За месяц одна тренировка; плитка показала «\(workoutsTile.label)»")
        XCTAssertTrue(app.descendants(matching: .any)["analytics.muscleMap"].exists, "Должна быть карта нагрузки мышц")
    }

    private func finishWorkoutWithOneSet(_ app: XCUIApplication) {
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

        let exerciseLink = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", exerciseName)).firstMatch
        exerciseLink.waitUntilVisible()
        exerciseLink.tap()

        let logSetButton = app.buttons["exerciseLog.addSet"]
        XCTAssertTrue(logSetButton.waitForExistence(timeout: 5))
        let deadline = Date().addingTimeInterval(5)
        while !logSetButton.isEnabled, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        logSetButton.tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let finishButton = app.buttons["Завершить"]
        finishButton.waitUntilVisible()
        finishButton.tap()
    }
}
