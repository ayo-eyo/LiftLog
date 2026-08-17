import XCTest

/// Regression: viewing an unstarted plan that already shows its own «Начать»
/// button also kept the global tab-bar accessory's «Начать тренировку» button
/// visible underneath it — two buttons doing an overlapping "start" action on
/// the same screen. The accessory should hide itself while the plan screen's
/// own start button is showing, and reappear once it isn't.
final class WorkoutStartAccessoryUITests: XCTestCase {
    @MainActor
    func test_единственнаяКнопкаНачатьНаЭкранеНезапущенногоПлана() throws {
        let app = AppLauncher.launch()

        let globalStartAccessory = app.buttons["root.startAccessory"]
        XCTAssertTrue(globalStartAccessory.waitForExistence(timeout: 5), "На списке тренировок должна быть глобальная кнопка старта")

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
            "Глобальная кнопка старта должна быть скрыта, пока на экране уже есть своя кнопка «Начать»"
        )

        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(
            globalStartAccessory.waitForExistence(timeout: 5),
            "После возврата к списку глобальная кнопка старта должна снова появиться"
        )
    }
}
