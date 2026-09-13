import XCTest

/// Регрессия: во время активной тренировки кнопка «Копировать» в тулбаре
/// пушила навигацию на неактивную копию, у которой нет ни «Завершить»/«Закрыть»
/// (эти кнопки показываются только для `workout.isActive`), ни «Начать» (он
/// скрыт, пока есть другая активная тренировка) — пользователь оставался на
/// экране без единой доступной кнопки.
final class WorkoutActiveScreenUITests: XCTestCase {
    @MainActor
    func test_копированиеНедоступноВоВремяАктивнойТренировки() throws {
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

        let addSetButton = app.buttons["Добавить подход"]
        addSetButton.waitUntilVisible()
        addSetButton.tap()

        let doneButton = app.buttons["Готово"]
        doneButton.waitUntilVisible()
        doneButton.tap()

        let startButton = app.buttons["Начать"]
        startButton.waitUntilVisible()
        startButton.tap()

        XCTAssertFalse(
            app.buttons["workoutDetail.copyButton"].exists,
            "Кнопка «Копировать» не должна быть доступна во время активной тренировки"
        )
    }

    @MainActor
    func test_остатокПодходовВиденИУменьшаетсяПослеЗаписи() throws {
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

        // Two planned positions, so logging one set still leaves a visible remainder.
        let addPlannedSetButton = app.buttons["Добавить подход"]
        addPlannedSetButton.waitUntilVisible()
        addPlannedSetButton.tap()
        addPlannedSetButton.tap()

        app.buttons["Готово"].tap()

        let startButton = app.buttons["Начать"]
        startButton.waitUntilVisible()
        startButton.tap()

        let progressLabel = app.staticTexts["workoutDetail.exerciseProgress.0"]
        progressLabel.waitUntilVisible()
        XCTAssertEqual(progressLabel.label, "0 из 2 подходов", "До записи подходов остаток должен показывать полный план")

        let exerciseNavLink = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Barbell Bench Press - Medium Grip")).firstMatch
        exerciseNavLink.waitUntilVisible()
        exerciseNavLink.tap()

        let logSetButton = app.buttons["Добавить подход"]
        logSetButton.waitUntilVisible()
        logSetButton.tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()

        progressLabel.waitUntilVisible()
        XCTAssertEqual(progressLabel.label, "1 из 2 подходов", "После записи подхода остаток должен уменьшиться")
    }
}
