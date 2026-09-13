import Testing
import Foundation
import SwiftData
@testable import LiftLog

@Suite("Автопереход: следующее упражнение")
struct WorkoutFlowTests {
    @Test("следующим становится ближайшее незакрытое по порядку тренировки")
    func nextIsTheNearestUnfulfilledForward() throws {
        let store = try TestStore.open()
        let a = Fixtures.exercise("A", in: store.context)
        let b = Fixtures.exercise("B", in: store.context)
        let c = Fixtures.exercise("C", in: store.context)
        let workout = Fixtures.workout(items: [(a, 60, 8), (b, 60, 8), (c, 60, 8)], in: store.context)
        workout.logSet(weight: 60, reps: 8, for: a, context: store.context)

        #expect(workout.nextUnfulfilledExercise(after: a)?.name == "B")
    }

    @Test("закрытые упражнения пропускаются")
    func closedExercisesAreSkipped() throws {
        let store = try TestStore.open()
        let a = Fixtures.exercise("A", in: store.context)
        let b = Fixtures.exercise("B", in: store.context)
        let c = Fixtures.exercise("C", in: store.context)
        let workout = Fixtures.workout(items: [(a, 60, 8), (b, 60, 8), (c, 60, 8)], in: store.context)
        workout.logSet(weight: 60, reps: 8, for: a, context: store.context)
        workout.logSet(weight: 60, reps: 8, for: b, context: store.context)

        #expect(workout.nextUnfulfilledExercise(after: a)?.name == "C")
    }

    @Test("если впереди незакрытых нет, возвращаемся к пропущенному в начале")
    func wrapsToTheStartWhenNothingIsLeftForward() throws {
        let store = try TestStore.open()
        let a = Fixtures.exercise("A", in: store.context)
        let b = Fixtures.exercise("B", in: store.context)
        let c = Fixtures.exercise("C", in: store.context)
        let workout = Fixtures.workout(items: [(a, 60, 8), (b, 60, 8), (c, 60, 8)], in: store.context)
        workout.logSet(weight: 60, reps: 8, for: b, context: store.context)
        workout.logSet(weight: 60, reps: 8, for: c, context: store.context)

        #expect(workout.nextUnfulfilledExercise(after: c)?.name == "A")
    }

    @Test("текущее упражнение себя не предлагает, упражнение без плана не предлагается, а без кандидатов возвращается nil")
    func selectionExcludesCurrentAndUnplannedAndFallsBackToNil() throws {
        let store = try TestStore.open()
        let current = Fixtures.exercise("Текущее", in: store.context)
        // No `WorkoutItem` for `noPlan` at all — the only way an exercise has zero
        // planned positions (see `plannedSetCount`'s doc).
        let noPlan = Fixtures.exercise("Без плана", in: store.context)
        let workout = Fixtures.workout(items: [(current, 60, 8)], in: store.context)

        // (a) `current` itself still has remaining sets, but is never offered.
        #expect(workout.nextUnfulfilledExercise(after: current) == nil)

        // (b) the plan-less exercise is never offered either, even with no sets logged.
        workout.logSet(weight: 60, reps: 8, for: noPlan, context: store.context)
        #expect(workout.nextUnfulfilledExercise(after: current) == nil)

        // (c) everything with a plan is closed → nil.
        workout.logSet(weight: 60, reps: 8, for: current, context: store.context)
        #expect(workout.nextUnfulfilledExercise(after: current) == nil)
    }

    @Test("порядок берётся после перестановки упражнений")
    func orderReflectsMoveExercise() throws {
        let store = try TestStore.open()
        let a = Fixtures.exercise("A", in: store.context)
        let b = Fixtures.exercise("B", in: store.context)
        let c = Fixtures.exercise("C", in: store.context)
        let workout = Fixtures.workout(items: [(a, 60, 8), (b, 60, 8), (c, 60, 8)], in: store.context)

        // A B C → C A B
        workout.moveExercise(from: IndexSet(integer: 2), to: 0)
        #expect(workout.orderedExercises.map(\.name) == ["C", "A", "B"])

        workout.logSet(weight: 60, reps: 8, for: c, context: store.context)
        #expect(workout.nextUnfulfilledExercise(after: c)?.name == "A")
    }

    @Test("телефон и снапшот для часов выбирают одно и то же следующее упражнение", arguments: [0, 1, 2, 3])
    func phoneAndWatchAgreeOnTheNextExercise(layout: Int) throws {
        let store = try TestStore.open()
        let a = Fixtures.exercise("A", in: store.context)
        let b = Fixtures.exercise("B", in: store.context)
        let c = Fixtures.exercise("C", in: store.context)
        let workout = Fixtures.workout(items: [(a, 60, 8), (b, 60, 8), (c, 60, 8)], in: store.context)

        switch layout {
        case 0:
            // Nothing logged yet.
            break
        case 1:
            // A closed, B/C open.
            workout.logSet(weight: 60, reps: 8, for: a, context: store.context)
        case 2:
            // A and B closed, only C open.
            workout.logSet(weight: 60, reps: 8, for: a, context: store.context)
            workout.logSet(weight: 60, reps: 8, for: b, context: store.context)
        default:
            // Reordered (C A B), then A closed.
            workout.moveExercise(from: IndexSet(integer: 2), to: 0)
            workout.logSet(weight: 60, reps: 8, for: a, context: store.context)
        }

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())
        manager.pushSnapshot(for: workout)
        let snapshot = try #require(manager.lastSnapshot)

        for exercise in [a, b, c] {
            let fromWorkout = workout.nextUnfulfilledExercise(after: exercise)?.syncID
            let fromSnapshot = snapshot.nextUnfulfilledExercise(after: exercise.syncID)?.id
            #expect(fromWorkout == fromSnapshot, "разошлись для \(exercise.name)")
        }
    }

    @Test("переход делается только на подходе, который закрывает упражнение")
    func advanceOnlyTriggersOnTheClosingSet() throws {
        let store = try TestStore.open()
        let a = Fixtures.exercise("A", in: store.context)
        let b = Fixtures.exercise("B", in: store.context)
        let workout = Fixtures.workout(items: [(a, 60, 8), (a, 60, 8), (b, 60, 8)], in: store.context)

        // 0 из 2 → 1 из 2: остаётся на месте.
        var wasFulfilled = workout.isSetPlanFulfilled(for: a)
        workout.logSet(weight: 60, reps: 8, for: a, context: store.context)
        #expect(WorkoutFlow.advance(after: a, wasFulfilled: wasFulfilled, in: workout) == .stay)

        // 1 из 2 → 2 из 2, есть незакрытые: переход на B.
        wasFulfilled = workout.isSetPlanFulfilled(for: a)
        workout.logSet(weight: 60, reps: 8, for: a, context: store.context)
        #expect(WorkoutFlow.advance(after: a, wasFulfilled: wasFulfilled, in: workout) == .next(b))

        // 2 из 2 → 3 из 2 (подход сверх плана): остаётся на месте, не дёргает снова.
        wasFulfilled = workout.isSetPlanFulfilled(for: a)
        workout.logSet(weight: 60, reps: 8, for: a, context: store.context)
        #expect(WorkoutFlow.advance(after: a, wasFulfilled: wasFulfilled, in: workout) == .stay)

        // Закрываем B — других незакрытых нет: план выполнен.
        wasFulfilled = workout.isSetPlanFulfilled(for: b)
        workout.logSet(weight: 60, reps: 8, for: b, context: store.context)
        #expect(WorkoutFlow.advance(after: b, wasFulfilled: wasFulfilled, in: workout) == .planFulfilled)
    }

    @Test("после смены упражнения предзаполнение берётся уже от нового")
    func prefillFollowsTheNewExerciseAfterAdvancing() throws {
        let store = try TestStore.open()
        let a = Fixtures.exercise("A", in: store.context)
        let b = Fixtures.exercise("B", in: store.context)
        let workout = Fixtures.workout(items: [(a, 60, 8), (b, 100, 5)], in: store.context)

        let prefillForA = WorkoutExerciseLogView.prefill(workout: workout, exercise: a)
        #expect(prefillForA.weight == 60)
        #expect(prefillForA.reps == 8)

        let prefillForB = WorkoutExerciseLogView.prefill(workout: workout, exercise: b)
        #expect(prefillForB.weight == 100)
        #expect(prefillForB.reps == 5)
    }
}
