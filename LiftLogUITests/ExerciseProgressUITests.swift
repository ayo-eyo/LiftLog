import XCTest

/// FR-2 of plans/features/progress-analytics: «Вся история упражнения» in a finished
/// workout opens the progress screen — the weight record tile, the chart placeholder for a
/// single session, and no standalone set input any more (decision 14).
final class ExerciseProgressUITests: XCTestCase {
    @MainActor
    func test_историяУпражненияПоказываетРекордВесаБезВводаПодхода() throws {
        let app = AppLauncher.launch()

        app.buttons["workoutList.addWorkout"].tap()

        let addExerciseButton = app.buttons["Добавить упражнение"]
        addExerciseButton.waitUntilVisible()
        addExerciseButton.tap()

        let searchField = app.searchFields["Поиск упражнения"]
        searchField.waitUntilVisible()
        searchField.tap()
        searchField.typeText("Barbell Bench Press - Medium Grip")

        let exerciseRow = app.buttons["Barbell Bench Press - Medium Grip"]
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

        let exerciseNavLink = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Barbell Bench Press - Medium Grip")).firstMatch
        exerciseNavLink.waitUntilVisible()
        exerciseNavLink.tap()

        let logSetButton = app.buttons["Добавить подход"]
        logSetButton.waitUntilVisible()
        logSetButton.tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()

        let finishButton = app.buttons["Завершить"]
        finishButton.waitUntilVisible()
        finishButton.tap()

        app.cells.firstMatch.waitUntilVisible()
        app.cells.firstMatch.tap()

        let historyLink = app.buttons["Вся история упражнения"]
        historyLink.waitUntilVisible()
        historyLink.tap()

        let recordTile = app.descendants(matching: .any)["exerciseProgress.recordWeight"]
        XCTAssertTrue(recordTile.waitForExistence(timeout: 5), "Экран прогресса должен показать плитку рекорда веса")
        XCTAssertTrue(recordTile.label.contains("20"), "Рекорд веса — единственный подход, 20 кг; плитка показала «\(recordTile.label)»")

        XCTAssertTrue(
            app.descendants(matching: .any)["exerciseProgress.chartPlaceholder"].exists,
            "При одной тренировке вместо графика должна быть подсказка"
        )
        XCTAssertFalse(app.buttons["Добавить подход"].exists, "Ввода подхода вне тренировки на экране прогресса быть не должно")
    }
}
