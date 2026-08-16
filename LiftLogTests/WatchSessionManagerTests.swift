import Testing
import Foundation
import SwiftData
@testable import LiftLog

/// Exercises `WatchSessionManager`'s message handling directly (`apply`/`logSet`/
/// `pushSnapshot` are `internal`, not `private`, exactly so tests can reach them —
/// see the `create-tests` skill's seam table). Each test builds its own instance
/// rather than using `.shared`, so tests can run in parallel without sharing state.
@Suite("WatchSessionManager — команды с часов")
struct WatchSessionManagerTests {
    @Test("skipRest останавливает таймер и пушит обновлённый снапшот без активного отдыха")
    func skipRestPushesUpdatedSnapshot() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)

        let restTimer = Fixtures.restTimer()
        restTimer.start(duration: 120, exerciseName: exercise.name)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: restTimer)
        manager.pushSnapshot(for: workout)
        #expect(manager.lastSnapshot?.restEndDate != nil)

        var reply: [String: Any]?
        manager.apply(WatchSyncFixtures.skipRestMessage(), context: store.context) { reply = $0 }

        #expect(restTimer.endDate == nil)
        #expect(manager.lastSnapshot?.restEndDate == nil, "снапшот после skipRest всё ещё несёт старый restEndDate")
        #expect((reply?["ok"] as? Bool) == true)
    }

    @Test("повторная доставка одной и той же команды (по commandID) не логирует подход дважды")
    func duplicateCommandIDIsIdempotent() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())

        let command = WatchSyncFixtures.logSetCommand(workoutID: workout.syncID, exerciseID: exercise.syncID)

        let first = manager.logSet(command, context: store.context)
        let second = manager.logSet(command, context: store.context)

        #expect(first != nil)
        #expect(second != nil)
        #expect(workout.setsFor(exercise).count == 1)
        #expect(try store.count(WorkoutSet.self) == 1)
    }

    @Test("команды с разными commandID логируют отдельные подходы")
    func distinctCommandIDsBothApply() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())

        let first = WatchSyncFixtures.logSetCommand(workoutID: workout.syncID, exerciseID: exercise.syncID, weight: 60, reps: 8)
        let second = WatchSyncFixtures.logSetCommand(workoutID: workout.syncID, exerciseID: exercise.syncID, weight: 65, reps: 6)

        _ = manager.logSet(first, context: store.context)
        _ = manager.logSet(second, context: store.context)

        #expect(workout.setsFor(exercise).count == 2)
    }

    @Test("снапшот вычисляется и сохраняется независимо от состояния активации WCSession, чтобы его можно было переслать позже")
    func pushSnapshotStoresSnapshotForLaterResend() throws {
        // Regression: the old `pushSnapshot` guarded on `activationState == .activated`
        // *before* computing anything, so a push that raced activation was lost until
        // the next unrelated workout change. `lastSnapshot` didn't exist at all before
        // this fix — this test would have failed to compile against the old code.
        let store = try TestStore.open()
        let workout = Fixtures.workout(in: store.context)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())
        manager.pushSnapshot(for: workout)

        #expect(manager.lastSnapshot?.workoutID == workout.syncID)
    }

    @Test("снапшот идущей тренировки перечисляет упражнения в порядке плана")
    func snapshotListsExercisesInPlanOrder() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let squat = Fixtures.exercise("Присед", in: store.context)
        let workout = Fixtures.workout(in: store.context)
        workout.addExercise(squat, weight: 100, reps: 5, context: store.context)
        workout.addExercise(bench, weight: 60, reps: 8, context: store.context)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())
        manager.pushSnapshot(for: workout)

        #expect(manager.lastSnapshot?.exercises.map(\.name) == ["Присед", "Жим лёжа"])
    }

    @Test("план (не начатая тренировка) не уходит на часы — снапшот пуст")
    func planDoesNotReachWatch() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let plan = Fixtures.workout(startedAt: nil, items: [(bench, 60, 8)], in: store.context)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())
        manager.pushSnapshot(for: plan)

        #expect(manager.lastSnapshot == nil)
    }

    @Test("завершённая тренировка не уходит на часы — снапшот пуст")
    func completedWorkoutDoesNotReachWatch() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [bench], in: store.context)
        workout.finish()

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())
        manager.pushSnapshot(for: workout)

        #expect(manager.lastSnapshot == nil)
    }

    @Test("фолбэк по имени всё ещё находит нужное упражнение, если syncID не совпал")
    func nameFallbackStillLogsToCorrectExercise() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise("Жим лёжа", in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())

        // exerciseID не совпадает ни с одним syncID — часы прислали устаревший снапшот.
        let command = WatchSyncFixtures.logSetCommand(
            workoutID: workout.syncID,
            exerciseID: UUID(),
            exerciseName: "Жим лёжа"
        )

        let info = manager.logSet(command, context: store.context)

        #expect(info?.name == "Жим лёжа")
        #expect(workout.setsFor(exercise).count == 1)
    }
}
