import XCTest

/// The global tab-bar accessory is a resume affordance only — it exists purely to get
/// back to the one workout that's already active, never to start a new one from an
/// arbitrary screen. It must stay absent whenever nothing is active (including while a
/// plan screen shows its own «Начать» button), and appear only once a workout starts.
final class WorkoutStartAccessoryUITests: XCTestCase {
    @MainActor
    func test_глобальнаяКнопкаТолькоДляВозвратаКАктивнойТренировке() throws {
        let app = AppLauncher.launch()

        let globalStartAccessory = app.buttons["root.startAccessory"]
        XCTAssertFalse(globalStartAccessory.exists, "Без активной тренировки глобальной кнопки старта быть не должно")

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

        app.buttons["Готово"].tap()

        let ownStartButton = app.buttons["Начать"]
        ownStartButton.waitUntilVisible()
        XCTAssertFalse(
            globalStartAccessory.exists,
            "Пока план ещё не начат, глобальной кнопки тоже не должно быть"
        )

        ownStartButton.tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(
            globalStartAccessory.waitForExistence(timeout: 5),
            "После старта тренировки глобальная кнопка должна появиться, чтобы можно было вернуться к ней"
        )
    }
}
