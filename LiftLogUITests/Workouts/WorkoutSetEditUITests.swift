import XCTest

/// Editing a logged set should change its values in place, without deleting
/// and re-logging it — covers the one place that lacked the tap-to-edit
/// affordance already used by `WorkoutExerciseLogView`/`ExerciseDetailView`:
/// a completed workout's set list in `WorkoutDetailView`. Drives the
/// weight/reps steppers rather than typing: clearing the text fields (via
/// either select-all or backspaces) was unreliable under XCUITest, silently
/// leaving the old digits in place and inserting new ones in front of them.
final class WorkoutSetEditUITests: XCTestCase {
    @MainActor
    func test_редактированиеЗалогированногоПодходаВЗавершённойТренировке() throws {
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

        let setRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "20 кг")).firstMatch
        XCTAssertTrue(setRow.waitForExistence(timeout: 5), "Залогированный подход (20 кг × 10) должен быть виден в завершённой тренировке")
        setRow.tap()

        let doneEditButton = app.buttons["Готово"]
        XCTAssertTrue(doneEditButton.waitForExistence(timeout: 5), "Экран редактирования подхода должен открыться")
        Thread.sleep(forTimeInterval: 0.5)

        // Weight stepper: step 0.25 (`WeightInputRow`), two taps → 20 + 0.5 = 20,5.
        let weightIncrement = app.buttons.matching(identifier: "Increment").element(boundBy: 0)
        weightIncrement.tap()
        Thread.sleep(forTimeInterval: 0.5)
        weightIncrement.tap()
        Thread.sleep(forTimeInterval: 0.5)

        // Reps stepper: step 1, two taps → 10 + 2 = 12.
        let repsIncrement = app.buttons.matching(identifier: "Increment").element(boundBy: 1)
        repsIncrement.tap()
        Thread.sleep(forTimeInterval: 0.5)
        repsIncrement.tap()
        Thread.sleep(forTimeInterval: 0.5)

        doneEditButton.tap()

        // `SetRow` is one accessibility element ("20,5 кг, 12 повторов"), not separate
        // weight/reps texts — so the row is found by its composed label.
        let editedRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "20,5 кг, 12 повторов")).firstMatch
        XCTAssertTrue(editedRow.waitForExistence(timeout: 5), "После редактирования подход должен показывать новый вес и повторы")
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "20 кг")).firstMatch.exists,
            "Старое значение веса не должно остаться в подходе после редактирования"
        )
    }
}
