import XCTest

/// FR-2's whole happy path in one test: logging the last planned set of an exercise
/// moves the screen on to the next unfulfilled one by itself, and once nothing is left
/// unfulfilled the screen offers to finish instead of guessing. One test on the flow
/// beats several on its branches — those are already covered by `WorkoutFlowTests`.
final class WorkoutAutoAdvanceUITests: XCTestCase {
    @MainActor
    func test_автопереходНаСледующееУпражнениеИПредложениеЗавершить() throws {
        let app = AppLauncher.launch()

        app.buttons["workoutList.addWorkout"].tap()

        addExercise(app, name: "Barbell Bench Press - Medium Grip")
        addExercise(app, name: "Barbell Squat")

        let startButton = app.buttons["Начать"]
        startButton.waitUntilVisible()
        startButton.tap()

        let firstExerciseLink = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Barbell Bench Press - Medium Grip")).firstMatch
        firstExerciseLink.waitUntilVisible()
        firstExerciseLink.tap()

        logSet(app)

        // The single planned set just closed the first exercise — the screen should
        // have swapped to the second one in place, no navigation involved.
        let squatTitle = app.navigationBars["Barbell Squat"]
        XCTAssertTrue(squatTitle.waitForExistence(timeout: 5), "После закрытия первого упражнения экран должен сам показать второе")

        logSet(app)

        // Nothing unfulfilled is left — the banner offers to finish instead of
        // guessing where to go. Queried via `.descendants(matching: .any)` rather than
        // `.otherElements`: a bare `VStack`'s accessibility identifier doesn't reliably
        // surface under the `.other` element type without an explicit
        // `.accessibilityElement` treatment.
        let planFulfilledBanner = app.descendants(matching: .any)["exerciseLog.planFulfilled"]
        XCTAssertTrue(planFulfilledBanner.waitForExistence(timeout: 5), "После закрытия последнего упражнения должен появиться баннер «План выполнен»")

        app.buttons["Завершить тренировку"].tap()

        // The banner's own dismiss only pops back to `WorkoutDetailView`, now showing
        // the completed summary — its «Готово» toolbar button is the way out of the
        // `fullScreenCover` from there (see the comment on it for why).
        let doneButton = app.buttons["workoutDetail.doneButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5), "После завершения тренировки должна появиться кнопка «Готово»")
        doneButton.tap()

        // Wait for a concrete signal that the `fullScreenCover` actually closed —
        // asserting the accessory's absence right away would race the dismiss
        // animation — then check it's gone.
        let addWorkoutButton = app.buttons["workoutList.addWorkout"]
        XCTAssertTrue(addWorkoutButton.waitForExistence(timeout: 5), "После нажатия «Готово» должны вернуться к списку тренировок")
        XCTAssertFalse(app.buttons["root.startAccessory"].exists, "После завершения тренировки глобальная кнопка возврата должна исчезнуть")
    }

    private func addExercise(_ app: XCUIApplication, name: String) {
        let addExerciseButton = app.buttons["Добавить упражнение"]
        addExerciseButton.waitUntilVisible()
        addExerciseButton.tap()

        let searchField = app.searchFields["Поиск упражнения"]
        searchField.waitUntilVisible()
        searchField.tap()
        searchField.typeText(name)

        let exerciseRow = app.buttons[name]
        exerciseRow.waitUntilVisible()
        exerciseRow.tap()

        let addPlannedSetButton = app.buttons["Добавить подход"]
        addPlannedSetButton.waitUntilVisible()
        addPlannedSetButton.tap()

        app.buttons["Готово"].tap()
    }

    /// Taps the active exercise screen's «Добавить подход» — by its identifier, not
    /// its label, since the same label is also used by the plan-editing screen's own
    /// "add a planned position" button. Polls for `isEnabled`, not just existence:
    /// after an auto-advance, the new exercise's prefill loads via `.task(id:)`, and
    /// the button — same button, same identity, just relabeled/re-enabled in place —
    /// stays disabled until that lands, so a bare existence check can tap it too early
    /// and silently no-op.
    private func logSet(_ app: XCUIApplication) {
        let button = app.buttons["exerciseLog.addSet"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        let deadline = Date().addingTimeInterval(5)
        while !button.isEnabled, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(button.isEnabled, "Кнопка «Добавить подход» должна стать активной после подстановки плановых значений")
        button.tap()
    }
}
