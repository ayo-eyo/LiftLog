import Testing
import SwiftData
@testable import LiftLog

@Suite("Подходы: план и факт")
struct WorkoutSetProgressTests {
    @Test("ожидание считается по позициям плана, а не по числу упражнений")
    func plannedCountsPositionsNotExercises() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let squat = Fixtures.exercise("Присед", in: store.context)
        let workout = Fixtures.workout(
            items: [(bench, 60, 8), (bench, 65, 6), (squat, 100, 5)],
            in: store.context
        )

        #expect(workout.plannedSetCount(for: bench) == 2)
        #expect(workout.plannedSetCount(for: squat) == 1)
        #expect(workout.orderedExercises.count == 2)
    }

    @Test("факт считает подходы только этого упражнения и только этой тренировки")
    func loggedCountsOnlyThisWorkout() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let first = Fixtures.workout(exercises: [bench], in: store.context)
        let second = Fixtures.workout(exercises: [bench], in: store.context)
        Fixtures.log([(60, 8)], for: bench, in: first, context: store.context)
        Fixtures.log([(65, 6)], for: bench, in: second, context: store.context)

        #expect(first.loggedSetCount(for: bench) == 1)
        #expect(second.loggedSetCount(for: bench) == 1)
        #expect(bench.sets.count == 2)
    }

    @Test("остаток уменьшается с каждым подходом и не уходит в минус", arguments: [0, 1, 2, 3])
    func remainingCountsDownAndFloorsAtZero(loggedCount: Int) throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(items: [(bench, 60, 8), (bench, 60, 8)], in: store.context)
        for _ in 0..<loggedCount {
            workout.logSet(weight: 60, reps: 8, for: bench, context: store.context)
        }

        let expectedRemaining = [2, 1, 0, 0][loggedCount]
        #expect(workout.remainingSetCount(for: bench) == expectedRemaining)
        #expect(workout.loggedSetCount(for: bench) == loggedCount)
    }

    @Test("упражнение закрыто, когда записано не меньше подходов, чем запланировано")
    func fulfilledOnceLoggedReachesPlanned() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(items: [(bench, 60, 8), (bench, 60, 8)], in: store.context)

        workout.logSet(weight: 60, reps: 8, for: bench, context: store.context)
        #expect(workout.isSetPlanFulfilled(for: bench) == false)

        workout.logSet(weight: 60, reps: 8, for: bench, context: store.context)
        #expect(workout.isSetPlanFulfilled(for: bench))

        workout.logSet(weight: 60, reps: 8, for: bench, context: store.context)
        #expect(workout.isSetPlanFulfilled(for: bench))
        #expect(workout.loggedSetCount(for: bench) == 3)
    }

    @Test("упражнение без плановых позиций не считается закрытым и не даёт остатка")
    func exerciseWithNoPlanIsNeverFulfilled() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let squat = Fixtures.exercise("Присед", in: store.context)
        // `bench` has a planned position and gets fully worked; `squat` is logged
        // straight through `logSet` with no `WorkoutItem` at all — the only way an
        // exercise ends up with zero planned positions (see `plannedSetCount`'s doc).
        let workout = Fixtures.workout(items: [(bench, 60, 8)], in: store.context)
        workout.logSet(weight: 60, reps: 8, for: bench, context: store.context)
        workout.logSet(weight: 40, reps: 12, for: squat, context: store.context)

        #expect(workout.plannedSetCount(for: squat) == 0)
        #expect(workout.remainingSetCount(for: squat) == 0)
        #expect(workout.isSetPlanFulfilled(for: squat) == false)
        // The plan-less exercise doesn't block the workout-wide predicate.
        #expect(workout.isSetPlanFulfilled)
    }

    @Test("остаток 0 — это ровно та точка, где предзаполнение перестаёт брать план")
    func remainingZeroMatchesPlannedItemExhausted() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(items: [(bench, 60, 8), (bench, 65, 6)], in: store.context)

        workout.logSet(weight: 60, reps: 8, for: bench, context: store.context)
        workout.logSet(weight: 65, reps: 6, for: bench, context: store.context)

        #expect(workout.remainingSetCount(for: bench) == 0)
        #expect(workout.defaultWeight(for: bench) == nil)
        #expect(workout.defaultReps(for: bench) == nil)
    }

    @Test("удаление позиции плана и удаление подхода пересчитывают счётчики сразу")
    func deletionsRecalculateImmediately() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(items: [(bench, 60, 8), (bench, 60, 8), (bench, 60, 8)], in: store.context)
        workout.logSet(weight: 60, reps: 8, for: bench, context: store.context)
        workout.logSet(weight: 60, reps: 8, for: bench, context: store.context)
        #expect(workout.plannedSetCount(for: bench) == 3)
        #expect(workout.isSetPlanFulfilled(for: bench) == false)

        // Deleting a planned position drops the expectation from 3 to 2 — immediately
        // enough that 2 logged now fulfills it, with no refetch in between.
        let lastItem = workout.sortedItems.last { $0.exercise?.persistentModelID == bench.persistentModelID }
        workout.deleteItem(try #require(lastItem), context: store.context)
        #expect(workout.plannedSetCount(for: bench) == 2)
        #expect(workout.isSetPlanFulfilled(for: bench))

        // Deleting a logged set drops the fact back down, un-fulfilling it again.
        let loggedSet = try #require(workout.setsFor(bench).first)
        WorkoutSet.delete(loggedSet, context: store.context)
        #expect(workout.loggedSetCount(for: bench) == 1)
        #expect(workout.isSetPlanFulfilled(for: bench) == false)
    }

    @Test("план тренировки отработан только когда закрыты все упражнения с планом")
    func wholeWorkoutFulfilledRequiresEveryPlannedExercise() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let squat = Fixtures.exercise("Присед", in: store.context)
        let workout = Fixtures.workout(
            items: [(bench, 60, 8), (bench, 60, 8), (squat, 100, 5), (squat, 100, 5)],
            in: store.context
        )

        Fixtures.log([(60, 8), (60, 8)], for: bench, in: workout, context: store.context)
        Fixtures.log([(100, 5)], for: squat, in: workout, context: store.context)
        #expect(workout.isSetPlanFulfilled == false)

        workout.logSet(weight: 100, reps: 5, for: squat, context: store.context)
        #expect(workout.isSetPlanFulfilled)
    }
}
