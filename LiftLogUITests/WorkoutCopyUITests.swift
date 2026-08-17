import XCTest

/// Regression: tapping «Копировать» on a plan workout pushed a second
/// `WorkoutDetailView` (the copy) via `.navigationDestination(item:)` from
/// within a `WorkoutDetailView` of the same type — recursing into the same
/// view type on the same navigation stack sent SwiftUI's view-graph diffing
/// into a runaway loop and froze the app, independent of item count (an
/// empty plan reproduced it too). The fix creates the copy and returns to
/// the list instead of navigating into it.
final class WorkoutCopyUITests: XCTestCase {
    @MainActor
    func test_копированиеПланаВозвращаетКСпискуБезЗависания() throws {
        let app = AppLauncher.launch()

        app.buttons["workoutList.addWorkout"].tap()

        let nameField = app.textFields["Название тренировки"]
        nameField.waitUntilVisible()
        nameField.tap()
        nameField.typeText("Ноги")

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
        addSetButton.tap()
        addSetButton.tap()

        let doneButton = app.buttons["Готово"]
        doneButton.waitUntilVisible()
        doneButton.tap()

        let copyButton = app.buttons["workoutDetail.copyButton"]
        copyButton.waitUntilVisible()
        copyButton.tap()

        let addWorkoutButton = app.buttons["workoutList.addWorkout"]
        XCTAssertTrue(
            addWorkoutButton.waitForExistence(timeout: 10),
            "После копирования приложение должно остаться отзывчивым и вернуться к списку тренировок"
        )
        XCTAssertTrue(app.staticTexts["Ноги"].waitForExistence(timeout: 5))
    }
}
