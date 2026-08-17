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
}
