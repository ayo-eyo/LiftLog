import Testing
import Foundation
import SwiftData
import WatchConnectivity
@testable import LiftLog

/// Records what `WatchSessionManager.send` did without touching a real `WCSession` —
/// see the seam declared next to `WatchConnectivitySession` in `WatchSessionManager.swift`.
@MainActor
private final class FakeWatchConnectivitySession: WatchConnectivitySession {
    var activationState: WCSessionActivationState = .activated
    var isReachable = false
    private(set) var applicationContexts: [[String: Any]] = []
    private(set) var sentMessages: [[String: Any]] = []

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        applicationContexts.append(applicationContext)
    }

    func sendMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?, errorHandler: ((Error) -> Void)?) {
        sentMessages.append(message)
    }
}

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

    @Test("старый формат сообщения (без конверта WatchCommand) всё ещё применяется")
    func legacyLogSetMessageStillApplies() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())

        let command = WatchSyncFixtures.logSetCommand(workoutID: workout.syncID, exerciseID: exercise.syncID)
        var reply: [String: Any]?
        manager.apply(try WatchSyncFixtures.legacyLogSetMessage(command), context: store.context) { reply = $0 }

        #expect((reply?["ok"] as? Bool) == true)
        #expect(workout.setsFor(exercise).count == 1)
    }

    @Test("команда в конверте WatchCommand логирует подход и возвращает свежий контекст")
    func commandEnvelopeLogsSetAndRepliesWithContext() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())

        let command = WatchCommand.logSet(WatchSyncFixtures.logSetCommand(workoutID: workout.syncID, exerciseID: exercise.syncID))
        var reply: [String: Any]?
        manager.apply(try WatchSyncFixtures.commandMessage(command), context: store.context) { reply = $0 }

        #expect(workout.setsFor(exercise).count == 1)
        let data = try #require(reply?[WatchMessageKey.context] as? Data)
        let decoded = try JSONDecoder().decode(WatchContext.self, from: data)
        #expect(decoded.snapshot?.workoutID == workout.syncID)
        #expect(decoded.appliedCommandIDs.contains(command.commandID))
    }

    @Test("нераспознанное сообщение отвечает отказом и ничего не меняет в сторе")
    func malformedMessageIsRejected() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())

        var reply: [String: Any]?
        manager.apply(WatchSyncFixtures.malformedLogSetMessage(), context: store.context) { reply = $0 }

        #expect((reply?["ok"] as? Bool) == false)
        #expect(workout.sets.isEmpty)
    }
}

@Suite("WatchSessionManager — старт и завершение с часов")
struct WatchSessionManagerLifecycleTests {
    @Test("команда старта запускает план и он уходит на часы как идущая тренировка")
    func startCommandStartsThePlan() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let plan = Fixtures.workout(startedAt: nil, items: [(exercise, 60, 8)], in: store.context)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())

        let result = manager.start(WatchSyncFixtures.startCommand(workoutID: plan.syncID), context: store.context)

        #expect(result == .applied)
        #expect(plan.isActive)
        #expect(manager.lastSnapshot?.workoutID == plan.syncID)
    }

    @Test("старт отклоняется с конфликтом, если на телефоне уже идёт другая тренировка")
    func startIsRefusedWhileAnotherWorkoutIsActive() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let active = Fixtures.workout(exercises: [exercise], in: store.context)
        let plan = Fixtures.workout(startedAt: nil, items: [(exercise, 60, 8)], in: store.context)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())

        let result = manager.start(WatchSyncFixtures.startCommand(workoutID: plan.syncID), context: store.context)

        #expect(result == .conflict(active.syncID))
        #expect(plan.startedAt == nil)
    }

    @Test("повторная доставка команды старта не переставляет startedAt")
    func duplicateStartCommandIsIdempotent() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let plan = Fixtures.workout(startedAt: nil, items: [(exercise, 60, 8)], in: store.context)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())

        let command = WatchSyncFixtures.startCommand(workoutID: plan.syncID)
        _ = manager.start(command, context: store.context)
        let firstStartedAt = plan.startedAt
        let versionAfterFirst = plan.version
        _ = manager.start(command, context: store.context)

        #expect(plan.startedAt == firstStartedAt)
        #expect(plan.version == versionAfterFirst)
    }

    @Test("команда завершения проставляет completedAt, гасит отдых и снимает снапшот с часов")
    func finishCommandCompletesTheWorkout() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)
        Fixtures.log([(60, 8)], for: exercise, in: workout, context: store.context)

        let restTimer = Fixtures.restTimer()
        restTimer.start(duration: 120, exerciseName: exercise.name)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: restTimer)

        let applied = manager.finish(WatchSyncFixtures.finishCommand(workoutID: workout.syncID), context: store.context)

        #expect(applied)
        #expect(workout.completedAt != nil)
        #expect(restTimer.endDate == nil)
        #expect(manager.lastSnapshot == nil)
    }

    @Test("повторная доставка команды завершения не переставляет completedAt")
    func duplicateFinishCommandIsIdempotent() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())

        let command = WatchSyncFixtures.finishCommand(workoutID: workout.syncID)
        _ = manager.finish(command, context: store.context)
        let firstCompletedAt = workout.completedAt
        _ = manager.finish(command, context: store.context)

        #expect(workout.completedAt == firstCompletedAt)
    }

    @Test("подтверждения команд переживают завершение тренировки — иначе доставленная повторно команда применится дважды")
    func appliedCommandIDsOutliveTheWorkout() throws {
        // Regression: `pushSnapshot(for: nil)` used to clear the dedup set whenever no
        // workout was active, which made a redelivered `finish` (or a set redelivered
        // right after finishing) apply a second time.
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())

        let logCommand = WatchSyncFixtures.logSetCommand(workoutID: workout.syncID, exerciseID: exercise.syncID)
        _ = manager.logSet(logCommand, context: store.context)
        _ = manager.finish(WatchSyncFixtures.finishCommand(workoutID: workout.syncID), context: store.context)
        _ = manager.logSet(logCommand, context: store.context)

        #expect(workout.setsFor(exercise).count == 1)
    }

    @Test("завершение с часов переживает перечитывание стора")
    func finishSurvivesReload() throws {
        // Regression (technical-notes.md §5.1): nothing called `context.save()`, so a
        // command applied right before iOS suspends the backgrounded app never reached
        // disk — this test fails before the fix by finding `completedAt == nil` after
        // `reload()`.
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)
        let workoutSyncID = workout.syncID

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())

        var reply: [String: Any]?
        let command = WatchCommand.finish(WatchSyncFixtures.finishCommand(workoutID: workoutSyncID))
        manager.apply(try WatchSyncFixtures.commandMessage(command), context: store.context) { reply = $0 }
        #expect((reply?["ok"] as? Bool) == true)

        let freshContext = try store.reload()
        let reloaded = try freshContext.fetch(FetchDescriptor<Workout>()).first { $0.syncID == workoutSyncID }
        #expect(reloaded?.completedAt != nil)
    }

    @Test("подход с часов переживает перечитывание стора")
    func logSetSurvivesReload() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)
        let workoutSyncID = workout.syncID

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())

        let command = WatchCommand.logSet(WatchSyncFixtures.logSetCommand(workoutID: workoutSyncID, exerciseID: exercise.syncID, weight: 72.5, reps: 5))
        var reply: [String: Any]?
        manager.apply(try WatchSyncFixtures.commandMessage(command), context: store.context) { reply = $0 }
        #expect((reply?["ok"] as? Bool) == true)

        let freshContext = try store.reload()
        let reloaded = try freshContext.fetch(FetchDescriptor<Workout>()).first { $0.syncID == workoutSyncID }
        #expect(reloaded?.sets.count == 1)
        #expect(reloaded?.sets.first?.weight == 72.5)
        #expect(reloaded?.sets.first?.reps == 5)
    }

    @Test("завершение с неизвестным workoutID завершает идущую тренировку — активной может быть только одна")
    func finishWithUnknownWorkoutIDFallsBackToTheActiveWorkout() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let active = Fixtures.workout(exercises: [exercise], in: store.context)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())

        let applied = manager.finish(WatchSyncFixtures.finishCommand(workoutID: UUID()), context: store.context)

        #expect(applied)
        #expect(active.completedAt != nil)
    }

    @Test("завершение, когда завершать нечего, считается успехом и ничего не меняет")
    func finishWithNothingActiveIsANoOpSuccess() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        // A finished workout, not an active one — nothing for the command to act on.
        Fixtures.workout(completedAt: Fixtures.date(offset: 3600), exercises: [exercise], in: store.context)
        let countBefore = try store.count(Workout.self)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())

        let applied = manager.finish(WatchSyncFixtures.finishCommand(workoutID: UUID()), context: store.context)

        #expect(applied)
        #expect(try store.count(Workout.self) == countBefore)
        #expect(manager.lastSnapshot == nil)
    }

    @Test("подтверждение завершения уезжает на часы в контексте")
    func finishAcknowledgementRidesInTheContext() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())

        let command = WatchSyncFixtures.finishCommand(workoutID: workout.syncID)
        _ = manager.finish(command, context: store.context)

        #expect(manager.lastContext?.appliedCommandIDs.contains(command.commandID) == true)
    }
}

@Suite("WatchSessionManager — тренировку записывают часы")
struct WatchSessionManagerHealthRecordedTests {
    @Test("отметка с часов ставит флаг, поднимает версию на единицу и переживает перечитывание стора")
    func marksWorkoutAndPersists() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)
        let versionBefore = workout.version
        let syncID = workout.syncID

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())
        var deleted: [UUID] = []
        manager.deletePhoneHealthCopy = { deleted.append($0) }

        var reply: [String: Any]?
        let command = WatchSyncFixtures.healthRecordedCommand(workoutID: syncID)
        manager.apply(try WatchSyncFixtures.commandMessage(.healthRecorded(command)), context: store.context) { reply = $0 }

        #expect(workout.healthRecordedOnWatch)
        #expect(workout.version == versionBefore + 1)
        #expect(deleted.isEmpty, "идущую тренировку телефон ещё не сохранял — удалять нечего")
        #expect((reply?[WatchMessageKey.ok] as? Bool) == true)
        #expect(manager.lastContext?.appliedCommandIDs.contains(command.commandID) == true)

        let reloaded = try store.reload().fetch(FetchDescriptor<Workout>()).first { $0.syncID == syncID }
        #expect(reloaded?.healthRecordedOnWatch == true)
    }

    @Test("повторная доставка отметки не поднимает версию второй раз")
    func redeliveryIsIdempotent() throws {
        let store = try TestStore.open()
        let workout = Fixtures.workout(exercises: [Fixtures.exercise(in: store.context)], in: store.context)
        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())
        manager.deletePhoneHealthCopy = { _ in }

        let command = WatchSyncFixtures.healthRecordedCommand(workoutID: workout.syncID)
        manager.healthRecorded(command, context: store.context)
        let version = workout.version
        manager.healthRecorded(command, context: store.context)

        #expect(workout.version == version)
    }

    @Test("отметка для уже завершённой тренировки удаляет копию, которую успел сохранить телефон")
    func completedWorkoutDeletesPhoneCopy() throws {
        let store = try TestStore.open()
        let workout = Fixtures.workout(
            completedAt: Fixtures.date(offset: 3600),
            exercises: [Fixtures.exercise(in: store.context)],
            in: store.context
        )
        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())
        var deleted: [UUID] = []
        manager.deletePhoneHealthCopy = { deleted.append($0) }

        manager.healthRecorded(WatchSyncFixtures.healthRecordedCommand(workoutID: workout.syncID), context: store.context)

        #expect(deleted == [workout.syncID])
    }

    @Test("отметка для неизвестной тренировки — успех без изменений, а не ошибка на часах")
    func unknownWorkoutIsSuccess() throws {
        let store = try TestStore.open()
        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())
        var deleted: [UUID] = []
        manager.deletePhoneHealthCopy = { deleted.append($0) }

        var reply: [String: Any]?
        let command = WatchSyncFixtures.healthRecordedCommand(workoutID: UUID())
        manager.apply(try WatchSyncFixtures.commandMessage(.healthRecorded(command)), context: store.context) { reply = $0 }

        #expect((reply?[WatchMessageKey.ok] as? Bool) == true)
        #expect(deleted.isEmpty)
    }
}

@Suite("Workout.complete — общий путь завершения")
struct WorkoutCompletionTests {
    @Test("гасит отдых, проставляет время завершения, сохраняет на диск и снимает снапшот с часов")
    func completeRunsTheFullSequence() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)
        Fixtures.log([(60, 8)], for: exercise, in: workout, context: store.context)
        let workoutSyncID = workout.syncID

        let restTimer = Fixtures.restTimer()
        restTimer.start(duration: 120, exerciseName: exercise.name)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())
        manager.pushSnapshot(for: workout)

        Workout.complete(workout, restTimer: restTimer, context: store.context, watchSession: manager)

        #expect(restTimer.endDate == nil)
        #expect(workout.completedAt != nil)
        #expect(manager.lastSnapshot == nil)

        let freshContext = try store.reload()
        let reloaded = try freshContext.fetch(FetchDescriptor<Workout>()).first { $0.syncID == workoutSyncID }
        #expect(reloaded?.completedAt != nil)
    }
}

@Suite("WatchSessionManager — список планов для часов")
struct WatchSessionManagerPlanListTests {
    @Test("планы уходят на часы вместе с упражнениями и плановыми весами")
    func plansCarryTheirFullPlan() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let plan = Fixtures.workout(startedAt: nil, items: [(bench, 60, 8), (bench, 65, 6)], in: store.context)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())
        manager.refresh()

        let summary = try #require(manager.lastPlans.first { $0.id == plan.syncID })
        #expect(summary.exercises.map(\.name) == ["Жим лёжа"])
        #expect(summary.exercises.first?.plannedSets.map(\.weight) == [60, 65])
        #expect(summary.exercises.first?.plannedSets.map(\.reps) == [8, 6])
    }

    @Test("идущая и завершённая тренировки в список планов не попадают")
    func onlyUnstartedWorkoutsAreListedAsPlans() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let plan = Fixtures.workout(startedAt: nil, items: [(exercise, 60, 8)], in: store.context)
        let active = Fixtures.workout(exercises: [exercise], in: store.context)
        let completed = Fixtures.workout(completedAt: Fixtures.date(offset: 3600), exercises: [exercise], in: store.context)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())
        manager.refresh()

        #expect(manager.lastPlans.map(\.id) == [plan.syncID])
        #expect(manager.lastSnapshot?.workoutID == active.syncID)
        #expect(manager.lastPlans.contains { $0.id == completed.syncID } == false)
    }

    @Test("запрос контекста с часов пересобирает список планов, а не отвечает последним отправленным")
    func requestContextRebuildsPlansFromTheStore() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let known = Fixtures.workout(startedAt: nil, items: [(exercise, 60, 8)], in: store.context)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())
        manager.refresh()
        #expect(manager.lastPlans.map(\.id) == [known.syncID])

        // Появился уже после последнего пуша — ровно то, чего часам не хватало:
        // сами они попросить состояние раньше не могли.
        let fresh = Fixtures.workout(
            date: Fixtures.date(offset: 86_400),
            startedAt: nil,
            items: [(exercise, 70, 6)],
            in: store.context
        )

        var reply: [String: Any]?
        manager.apply(WatchSyncFixtures.requestContextMessage(), context: store.context) { reply = $0 }

        #expect(Set(manager.lastPlans.map(\.id)) == Set([known.syncID, fresh.syncID]))
        #expect((reply?[WatchMessageKey.ok] as? Bool) == true)

        let data = try #require(reply?[WatchMessageKey.context] as? Data)
        let answered = try WatchSyncFixtures.decoder.decode(WatchContext.self, from: data)
        #expect(Set(answered.plans.map(\.id)) == Set([known.syncID, fresh.syncID]))
    }

    @Test("refresh сам находит идущую тренировку в сторе")
    func refreshFindsTheActiveWorkout() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())
        manager.refresh()

        #expect(manager.lastSnapshot?.workoutID == workout.syncID)
    }

    @Test("снапшот несёт версию тренировки, чтобы часы могли сверить своё состояние")
    func snapshotCarriesTheVersion() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)
        Fixtures.log([(60, 8)], for: exercise, in: workout, context: store.context)

        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())
        manager.pushSnapshot(for: workout)

        #expect(manager.lastSnapshot?.version == workout.version)
    }
}

@Suite("WatchSessionManager — живой пуш через sendMessage")
struct WatchSessionManagerLivePushTests {
    @Test("когда часы на связи, снапшот уходит и через updateApplicationContext, и как живое сообщение")
    func reachableWatchGetsBothChannels() throws {
        // Regression: `updateApplicationContext` alone can sit undelivered for a long
        // while against an already-foreground watch app, which is what forced a relaunch
        // to see a set logged on the phone. Before the fix, `sentMessages` stayed empty
        // here.
        let store = try TestStore.open()
        let workout = Fixtures.workout(in: store.context)
        let session = FakeWatchConnectivitySession()
        session.isReachable = true

        let manager = WatchSessionManager()
        manager.session = session
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())
        manager.pushSnapshot(for: workout)

        #expect(session.applicationContexts.count == 1)
        #expect(session.sentMessages.count == 1)
        #expect(session.sentMessages.first?[WatchMessageKey.push] is Data)
    }

    @Test("когда часы не на связи, живое сообщение не отправляется — только updateApplicationContext")
    func unreachableWatchGetsOnlyApplicationContext() throws {
        let store = try TestStore.open()
        let workout = Fixtures.workout(in: store.context)
        let session = FakeWatchConnectivitySession()
        session.isReachable = false

        let manager = WatchSessionManager()
        manager.session = session
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())
        manager.pushSnapshot(for: workout)

        #expect(session.applicationContexts.count == 1)
        #expect(session.sentMessages.isEmpty)
    }

    @Test("живое сообщение несёт тот же WatchContext, что и updateApplicationContext")
    func livePushCarriesTheSameContext() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)
        let session = FakeWatchConnectivitySession()
        session.isReachable = true

        let manager = WatchSessionManager()
        manager.session = session
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())
        manager.pushSnapshot(for: workout)

        let pushed = try #require(session.sentMessages.first?[WatchMessageKey.push] as? Data)
        let decoded = try JSONDecoder().decode(WatchContext.self, from: pushed)
        #expect(decoded.snapshot?.workoutID == workout.syncID)
    }
}

@Suite("WatchSessionManager — порог рекорда в контексте")
struct WatchSessionManagerRecordWeightTests {
    @Test("упражнение в контексте несёт рекорд веса всей истории, включая идущую тренировку")
    func exerciseInfoCarriesRecordWeight() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        Fixtures.completedWorkout(bench, sets: [(80, 5)], on: Fixtures.day(0), in: store.context)
        let workout = Fixtures.workout(date: Fixtures.day(1), startedAt: Fixtures.day(1), exercises: [bench], in: store.context)
        workout.logSet(weight: 85, reps: 3, for: bench, now: Fixtures.day(1).addingTimeInterval(60), context: store.context)
        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())

        let command = WatchSyncFixtures.logSetCommand(workoutID: workout.syncID, exerciseID: bench.syncID, weight: 82.5, reps: 5)
        let info = try #require(manager.logSet(command, context: store.context))

        #expect(info.tracksRecords)
        #expect(info.recordWeight == 85)
    }

    @Test("часы по своему DTO решают о рекорде так же, как телефон по истории", arguments: [75.0, 80, 82.5, 0])
    func watchRecordCallMatchesPhone(weight: Double) throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        Fixtures.completedWorkout(bench, sets: [(70, 8), (80, 5)], on: Fixtures.day(0), in: store.context)
        let workout = Fixtures.workout(date: Fixtures.day(1), startedAt: Fixtures.day(1), exercises: [bench], in: store.context)
        let manager = WatchSessionManager()
        manager.start(modelContext: store.context, restTimer: Fixtures.restTimer())

        let watchSaysRecord = manager.exerciseInfo(for: bench, in: workout).isWeightRecord(weight)
        let set = workout.logSet(weight: weight, reps: 5, for: bench, now: Fixtures.day(1).addingTimeInterval(60), context: store.context)
        let phoneSaysRecord = ExerciseStats.recordBeaten(by: set.persistentModelID, in: ExerciseStats.samples(for: bench)) != nil

        #expect(watchSaysRecord == phoneSaysRecord)
        #expect(watchSaysRecord == (weight == 82.5))
    }
}
