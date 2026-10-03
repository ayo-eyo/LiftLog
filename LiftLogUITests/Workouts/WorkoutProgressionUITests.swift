import XCTest

/// FR-2 of plans/features/progression: finishing a workout whose plan was done brings up
/// «Следующая тренировка» with the step added (2,5 кг by default), and «Сохранить план»
/// puts the next workout at the top of the list with those numbers. A finished workout
/// keeps a «Спланировать следующую» button that opens the same screen.
final class WorkoutProgressionUITests: XCTestCase {
    private let exerciseQuery = "Barbell Bench Press - Medium Grip"
    private let exerciseName = "Жим штанги лёжа средним хватом"

    @MainActor
    func test_выполненныйПланДаётСледующуюТренировкуСПрибавкой() throws {
        let app = AppLauncher.launch()
        doPlannedSet(app)

        let finishButton = app.buttons["Завершить"]
        finishButton.waitUntilVisible()
        finishButton.tap()

        // The plan editor's default position is 20 кг × 10, logged as is — done, +2,5 кг.
        let position = app.buttons["nextPlan.position.0.0"]
        XCTAssertTrue(position.waitForExistence(timeout: 5), "После завершения должен открыться экран «Следующая тренировка»")
        XCTAssertTrue(position.label.contains("22,5×10"), "Выполненный план должен предложить 22,5×10; строка — «\(position.label)»")

        app.buttons["nextPlan.save"].tap()

        // The new plan is the top row; the finished workout is below it.
        let topRow = app.cells.firstMatch
        topRow.waitUntilVisible()
        topRow.tap()

        let plannedSummary = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "22,5 кг × 10")).firstMatch
        XCTAssertTrue(plannedSummary.waitForExistence(timeout: 5), "План следующей тренировки должен содержать 22,5 кг × 10")
        XCTAssertTrue(app.buttons["Начать"].exists, "Сохранённая следующая тренировка — ещё не начатый план")
    }

    @MainActor
    func test_завершённаяТренировкаОткрываетСледующуюПоКнопке() throws {
        let app = AppLauncher.launch()
        doPlannedSet(app)

        app.buttons["Завершить"].tap()
        app.skipNextWorkoutPlan()

        let finishedRow = app.cells.firstMatch
        finishedRow.waitUntilVisible()
        finishedRow.tap()

        let planNext = app.buttons["workoutDetail.planNext"]
        planNext.waitUntilVisible()
        planNext.tap()

        XCTAssertTrue(
            app.buttons["nextPlan.position.0.0"].waitForExistence(timeout: 5),
            "Кнопка у завершённой тренировки должна открыть «Следующая тренировка»"
        )
        // From a finished workout, closing the screen leaves you on that workout.
        app.buttons["nextPlan.skip"].tap()
        XCTAssertTrue(planNext.waitForExistence(timeout: 5), "После «Пропустить» остаёмся на завершённой тренировке")
    }

    /// New workout, one planned position (the editor's default 20 × 10), started, that
    /// position logged, back on the workout screen.
    private func doPlannedSet(_ app: XCUIApplication) {
        let addWorkout = app.buttons["workoutList.addWorkout"]
        addWorkout.waitUntilVisible()
        addWorkout.tap()

        let addExerciseButton = app.buttons["Добавить упражнение"]
        addExerciseButton.waitUntilVisible()
        addExerciseButton.tap()

        let searchField = app.searchFields["Поиск упражнения"]
        searchField.waitUntilVisible()
        searchField.tap()
        searchField.typeText(exerciseQuery)

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

        let logSetButton = app.buttons["Добавить подход"]
        logSetButton.waitUntilVisible()
        logSetButton.tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
    }
}
