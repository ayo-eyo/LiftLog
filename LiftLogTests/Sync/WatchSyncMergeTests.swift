import Testing
import Foundation
@testable import LiftLog

/// `WatchSyncMerge` is the watch's offline-queue logic. It lives in the shared
/// `WorkoutSyncModels.swift` (identical in both targets, guarded by the parity check)
/// precisely so it can be tested here — the watch target has no test target of its own.
@Suite("WatchSyncMerge — наложение оффлайн-очереди на состояние телефона")
struct WatchSyncMergeOverlayTests {
    @Test("неотправленные подходы уже видны в счётчике упражнения")
    func pendingSetsShowUpInTheCount() throws {
        let exerciseID = UUID()
        let workoutID = UUID()
        let snapshot = WatchSyncFixtures.snapshot(
            workoutID: workoutID,
            version: 3,
            exercises: [WatchSyncFixtures.exerciseInfo(id: exerciseID, setsLoggedCount: 1)]
        )
        let context = WatchSyncFixtures.context(snapshot: snapshot)
        let pending = [
            WatchSyncFixtures.pending(.logSet(WatchSyncFixtures.logSetCommand(workoutID: workoutID, exerciseID: exerciseID)), expectedVersion: 4),
            WatchSyncFixtures.pending(.logSet(WatchSyncFixtures.logSetCommand(workoutID: workoutID, exerciseID: exerciseID)), expectedVersion: 5)
        ]

        let merged = try #require(WatchSyncMerge.activeSnapshot(in: context, pending: pending))

        #expect(merged.exercises.first?.setsLoggedCount == 3)
        #expect(merged.version == 5)
    }

    @Test("дефолты следующего подхода берутся из плана по позиции с учётом очереди")
    func nextDefaultsAdvanceThroughThePlan() throws {
        let exerciseID = UUID()
        let workoutID = UUID()
        let snapshot = WatchSyncFixtures.snapshot(
            workoutID: workoutID,
            exercises: [WatchSyncFixtures.exerciseInfo(
                id: exerciseID,
                setsLoggedCount: 0,
                weight: 60,
                reps: 10,
                plannedSets: WatchSyncFixtures.plannedSets([(60, 10), (65, 8), (70, 6)])
            )]
        )
        let context = WatchSyncFixtures.context(snapshot: snapshot)
        let pending = [
            WatchSyncFixtures.pending(.logSet(WatchSyncFixtures.logSetCommand(workoutID: workoutID, exerciseID: exerciseID, weight: 60, reps: 10)), expectedVersion: 1)
        ]

        let merged = try #require(WatchSyncMerge.activeSnapshot(in: context, pending: pending))
        let exercise = try #require(merged.exercises.first)

        #expect(exercise.weight == 65)
        #expect(exercise.reps == 8)
    }

    @Test("когда план кончился, дефолтом становится последний записанный подход")
    func defaultsFallBackToLastLoggedSetPastThePlan() throws {
        let exerciseID = UUID()
        let workoutID = UUID()
        let snapshot = WatchSyncFixtures.snapshot(
            workoutID: workoutID,
            exercises: [WatchSyncFixtures.exerciseInfo(
                id: exerciseID,
                setsLoggedCount: 1,
                plannedSets: WatchSyncFixtures.plannedSets([(60, 10)])
            )]
        )
        let context = WatchSyncFixtures.context(snapshot: snapshot)
        let pending = [
            WatchSyncFixtures.pending(.logSet(WatchSyncFixtures.logSetCommand(workoutID: workoutID, exerciseID: exerciseID, weight: 72.5, reps: 5)), expectedVersion: 1)
        ]

        let merged = try #require(WatchSyncMerge.activeSnapshot(in: context, pending: pending))
        let exercise = try #require(merged.exercises.first)

        #expect(exercise.weight == 72.5)
        #expect(exercise.reps == 5)
    }

    @Test("неотправленная очередь уменьшает остаток и закрывает упражнение — офлайн-счётчик на часах")
    func pendingQueueClosesTheExerciseOffline() throws {
        let exerciseID = UUID()
        let workoutID = UUID()
        let snapshot = WatchSyncFixtures.snapshot(
            workoutID: workoutID,
            exercises: [WatchSyncFixtures.exerciseInfo(
                id: exerciseID,
                setsLoggedCount: 1,
                plannedSets: WatchSyncFixtures.plannedSets([(60, 8), (60, 8), (60, 8)])
            )]
        )
        let context = WatchSyncFixtures.context(snapshot: snapshot)
        let pending = [
            WatchSyncFixtures.pending(.logSet(WatchSyncFixtures.logSetCommand(workoutID: workoutID, exerciseID: exerciseID)), expectedVersion: 1),
            WatchSyncFixtures.pending(.logSet(WatchSyncFixtures.logSetCommand(workoutID: workoutID, exerciseID: exerciseID)), expectedVersion: 2)
        ]

        let merged = try #require(WatchSyncMerge.activeSnapshot(in: context, pending: pending))
        let exercise = try #require(merged.exercises.first)

        #expect(exercise.setsLoggedCount == 3)
        #expect(exercise.remainingSetCount == 0)
        #expect(exercise.isSetPlanFulfilled)
    }

    @Test("очередь другой тренировки не влияет на активную")
    func pendingForAnotherWorkoutIsIgnored() throws {
        let exerciseID = UUID()
        let snapshot = WatchSyncFixtures.snapshot(
            workoutID: UUID(),
            exercises: [WatchSyncFixtures.exerciseInfo(id: exerciseID, setsLoggedCount: 2)]
        )
        let context = WatchSyncFixtures.context(snapshot: snapshot)
        let pending = [
            WatchSyncFixtures.pending(.logSet(WatchSyncFixtures.logSetCommand(workoutID: UUID(), exerciseID: exerciseID)), expectedVersion: 1)
        ]

        let merged = try #require(WatchSyncMerge.activeSnapshot(in: context, pending: pending))

        #expect(merged.exercises.first?.setsLoggedCount == 2)
    }
}

@Suite("WatchSyncMerge — оффлайн-старт и завершение")
struct WatchSyncMergeLifecycleTests {
    @Test("план с неотправленной командой старта показывается как идущая тренировка")
    func locallyStartedPlanBecomesTheActiveWorkout() throws {
        let plan = WatchSyncFixtures.summary(
            name: "Грудь",
            version: 2,
            exercises: [WatchSyncFixtures.exerciseInfo(name: "Жим лёжа", plannedSets: WatchSyncFixtures.plannedSets([(60, 8)]))]
        )
        let context = WatchSyncFixtures.context(plans: [plan])
        let pending = [WatchSyncFixtures.pending(.start(WatchSyncFixtures.startCommand(workoutID: plan.id)), expectedVersion: 3)]

        let merged = try #require(WatchSyncMerge.activeSnapshot(in: context, pending: pending))

        #expect(merged.workoutID == plan.id)
        #expect(merged.name == "Грудь")
        #expect(merged.version == 3)
        #expect(merged.exercises.map(\.name) == ["Жим лёжа"])
    }

    @Test("локально начатый план исчезает из списка планов, чтобы его нельзя было начать дважды")
    func locallyStartedPlanLeavesThePlanList() throws {
        let plan = WatchSyncFixtures.summary()
        let other = WatchSyncFixtures.summary(name: "Спина")
        let context = WatchSyncFixtures.context(plans: [plan, other])
        let pending = [WatchSyncFixtures.pending(.start(WatchSyncFixtures.startCommand(workoutID: plan.id)), expectedVersion: 1)]

        let plans = WatchSyncMerge.plans(in: context, pending: pending)

        #expect(plans.map(\.id) == [other.id])
    }

    @Test("подходы, записанные в локально начатую тренировку, видны в ней же")
    func setsLoggedIntoALocallyStartedWorkoutShowUp() throws {
        let exerciseID = UUID()
        let plan = WatchSyncFixtures.summary(
            exercises: [WatchSyncFixtures.exerciseInfo(id: exerciseID, plannedSets: WatchSyncFixtures.plannedSets([(60, 8), (60, 8)]))]
        )
        let context = WatchSyncFixtures.context(plans: [plan])
        let pending = [
            WatchSyncFixtures.pending(.start(WatchSyncFixtures.startCommand(workoutID: plan.id)), expectedVersion: 1),
            WatchSyncFixtures.pending(.logSet(WatchSyncFixtures.logSetCommand(workoutID: plan.id, exerciseID: exerciseID)), expectedVersion: 2)
        ]

        let merged = try #require(WatchSyncMerge.activeSnapshot(in: context, pending: pending))

        #expect(merged.exercises.first?.setsLoggedCount == 1)
        #expect(merged.version == 2)
    }

    @Test("неотправленное завершение сразу убирает тренировку с экрана")
    func pendingFinishHidesTheWorkout() throws {
        let workoutID = UUID()
        let context = WatchSyncFixtures.context(snapshot: WatchSyncFixtures.snapshot(workoutID: workoutID))
        let pending = [WatchSyncFixtures.pending(.finish(WatchSyncFixtures.finishCommand(workoutID: workoutID)), expectedVersion: 1)]

        #expect(WatchSyncMerge.activeSnapshot(in: context, pending: pending) == nil)
    }

    @Test("завершение остаётся скрытым и после подтверждения по commandID — снапшот телефона тоже уже nil")
    func acknowledgedFinishStaysHidden() throws {
        let workoutID = UUID()
        let commandID = UUID()
        // No active snapshot on the phone any more — same as after it actually finished.
        let context = WatchSyncFixtures.context(snapshot: nil, appliedCommandIDs: [commandID])
        let pending = [WatchSyncFixtures.pending(.finish(WatchSyncFixtures.finishCommand(workoutID: workoutID, commandID: commandID)), expectedVersion: 1)]

        #expect(WatchSyncMerge.activeSnapshot(in: context, pending: pending) == nil)
        #expect(WatchSyncMerge.reconcile(pending: pending, with: context).isEmpty)
    }
}

@Suite("WatchSyncMerge — когда сообщать о неотправленном")
struct WatchSyncMergeQueueWarningTests {
    @Test("пустая очередь молчит")
    func emptyQueueIsSilent() throws {
        #expect(WatchSyncMerge.shouldWarnAboutQueue([], now: Fixtures.epoch) == false)
    }

    @Test("нормально уходящая очередь молчит: пара свежих записей — это рабочий режим, а не новость")
    func freshSmallQueueIsSilent() throws {
        let pending = WatchSyncFixtures.pendingSets(2, queuedAt: Fixtures.epoch)

        #expect(WatchSyncMerge.shouldWarnAboutQueue(pending, now: Fixtures.date(offset: 30)) == false)
    }

    @Test("ровно пять свежих записей ещё молчат, шестая — уже сообщает")
    func countThresholdIsAboveFive() throws {
        let five = WatchSyncFixtures.pendingSets(5, queuedAt: Fixtures.epoch)
        let six = WatchSyncFixtures.pendingSets(6, queuedAt: Fixtures.epoch)

        #expect(WatchSyncMerge.shouldWarnAboutQueue(five, now: Fixtures.date(offset: 10)) == false)
        #expect(WatchSyncMerge.shouldWarnAboutQueue(six, now: Fixtures.date(offset: 10)))
    }

    @Test("одна запись, висящая дольше пяти минут, сообщает о себе")
    func ageThresholdIsFiveMinutes() throws {
        let pending = WatchSyncFixtures.pendingSets(1, queuedAt: Fixtures.epoch)

        #expect(WatchSyncMerge.shouldWarnAboutQueue(pending, now: Fixtures.date(offset: 299)) == false)
        #expect(WatchSyncMerge.shouldWarnAboutQueue(pending, now: Fixtures.date(offset: 300)))
    }

    @Test("возраст считается по самой старой записи, а не по последней")
    func ageIsMeasuredFromTheOldestEntry() throws {
        let pending = WatchSyncFixtures.pendingSets(1, queuedAt: Fixtures.epoch)
            + WatchSyncFixtures.pendingSets(1, queuedAt: Fixtures.date(offset: 400))

        #expect(WatchSyncMerge.shouldWarnAboutQueue(pending, now: Fixtures.date(offset: 400)))
    }

    @Test("момент, когда очередь начнёт сообщать о себе — пять минут от самой старой записи")
    func warningDateIsOldestPlusDelay() throws {
        let pending = WatchSyncFixtures.pendingSets(2, queuedAt: Fixtures.date(offset: 60))

        #expect(WatchSyncMerge.queueWarningDate(pending) == Fixtures.date(offset: 360))
        #expect(WatchSyncMerge.queueWarningDate([]) == nil)
    }
}

@Suite("WatchSyncMerge — сверка очереди с телефоном")
struct WatchSyncMergeReconcileTests {
    @Test("команда, которую телефон подтвердил по commandID, уходит из очереди")
    func acknowledgedCommandLeavesTheQueue() throws {
        let workoutID = UUID()
        let appliedID = UUID()
        let applied = WatchSyncFixtures.pending(
            .logSet(WatchSyncFixtures.logSetCommand(workoutID: workoutID, exerciseID: UUID(), commandID: appliedID)),
            expectedVersion: 1
        )
        let stillPending = WatchSyncFixtures.pending(
            .logSet(WatchSyncFixtures.logSetCommand(workoutID: workoutID, exerciseID: UUID())),
            expectedVersion: 2
        )
        let context = WatchSyncFixtures.context(
            snapshot: WatchSyncFixtures.snapshot(workoutID: workoutID, version: 1),
            appliedCommandIDs: [appliedID]
        )

        let remaining = WatchSyncMerge.reconcile(pending: [applied, stillPending], with: context)

        #expect(remaining.map(\.id) == [stillPending.id])
    }

    @Test("если версия на телефоне уже догнала ожидаемую, команда считается доехавшей даже без подтверждения по ID")
    func versionRuleClearsCommandsWhoseAckAgedOut() throws {
        // The ack list is bounded, so after a long offline stretch confirmations can be
        // pushed out of the window — the version is what's left to go on.
        let workoutID = UUID()
        let entry = WatchSyncFixtures.pending(
            .logSet(WatchSyncFixtures.logSetCommand(workoutID: workoutID, exerciseID: UUID())),
            expectedVersion: 4
        )
        let context = WatchSyncFixtures.context(snapshot: WatchSyncFixtures.snapshot(workoutID: workoutID, version: 7))

        #expect(WatchSyncMerge.reconcile(pending: [entry], with: context).isEmpty)
    }

    @Test("отставшая версия телефона очередь не чистит — подход остаётся ждать")
    func lowerRemoteVersionKeepsTheQueue() throws {
        let workoutID = UUID()
        let entry = WatchSyncFixtures.pending(
            .logSet(WatchSyncFixtures.logSetCommand(workoutID: workoutID, exerciseID: UUID())),
            expectedVersion: 5
        )
        let context = WatchSyncFixtures.context(snapshot: WatchSyncFixtures.snapshot(workoutID: workoutID, version: 4))

        #expect(WatchSyncMerge.reconcile(pending: [entry], with: context).count == 1)
    }

    @Test("тренировку, о которой телефон вообще не сообщил, очередь по версии не чистит")
    func unknownWorkoutKeepsItsQueue() throws {
        let entry = WatchSyncFixtures.pending(
            .logSet(WatchSyncFixtures.logSetCommand(workoutID: UUID(), exerciseID: UUID())),
            expectedVersion: 1
        )
        let context = WatchSyncFixtures.context()

        #expect(WatchSyncMerge.reconcile(pending: [entry], with: context).count == 1)
    }

    @Test("команда старта остаётся в очереди, пока план всё ещё числится планом — даже если его версию подняли правкой на телефоне")
    func startSurvivesVersionBumpsFromPhoneSideEdits() throws {
        // Правка плана на телефоне (добавили упражнение) тоже двигает версию, и по
        // одной только версии старт выглядел бы применённым, хотя тренировка не начата.
        let plan = WatchSyncFixtures.summary(version: 9)
        let entry = WatchSyncFixtures.pending(.start(WatchSyncFixtures.startCommand(workoutID: plan.id)), expectedVersion: 3)
        let context = WatchSyncFixtures.context(plans: [plan])

        #expect(WatchSyncMerge.reconcile(pending: [entry], with: context).count == 1)
    }

    @Test("команда старта считается доехавшей, когда тренировка перестала быть планом")
    func startLandsWhenThePlanBecomesActive() throws {
        let workoutID = UUID()
        let entry = WatchSyncFixtures.pending(.start(WatchSyncFixtures.startCommand(workoutID: workoutID)), expectedVersion: 1)
        let context = WatchSyncFixtures.context(snapshot: WatchSyncFixtures.snapshot(workoutID: workoutID, version: 1))

        #expect(WatchSyncMerge.reconcile(pending: [entry], with: context).isEmpty)
    }

    @Test("завершение не выбрасывается из очереди, пока перед ним стоит непримененный старт")
    func finishWaitsForTheStartInFrontOfIt() throws {
        // Без учёта порядка finish выглядел бы применённым просто потому, что телефон
        // ещё не начал тренировку и она не активна.
        let plan = WatchSyncFixtures.summary()
        let start = WatchSyncFixtures.pending(.start(WatchSyncFixtures.startCommand(workoutID: plan.id)), expectedVersion: 1)
        let finish = WatchSyncFixtures.pending(.finish(WatchSyncFixtures.finishCommand(workoutID: plan.id)), expectedVersion: 2)
        let context = WatchSyncFixtures.context(plans: [plan])

        let remaining = WatchSyncMerge.reconcile(pending: [start, finish], with: context)

        #expect(remaining.map(\.id) == [start.id, finish.id])
    }

    @Test("подход не выбрасывается по версии, пока стоящий перед ним старт не доехал")
    func setWaitsForItsStart() throws {
        let plan = WatchSyncFixtures.summary(version: 5)
        let start = WatchSyncFixtures.pending(.start(WatchSyncFixtures.startCommand(workoutID: plan.id)), expectedVersion: 1)
        let set = WatchSyncFixtures.pending(
            .logSet(WatchSyncFixtures.logSetCommand(workoutID: plan.id, exerciseID: UUID())),
            expectedVersion: 2
        )
        let context = WatchSyncFixtures.context(plans: [plan])

        #expect(WatchSyncMerge.reconcile(pending: [start, set], with: context).count == 2)
    }

    @Test("неподтверждённое завершение остаётся в очереди, даже если телефон прислал контекст без активной тренировки")
    func unacknowledgedFinishStaysQueuedDespiteNoActiveSnapshot() throws {
        // Regression (technical-notes.md §5.3): `context.snapshot == nil` isn't proof
        // this specific `.finish` landed — a push can go out with no active workout for
        // all sorts of unrelated reasons (a race before the command even arrived,
        // another workout's push). Only the explicit ack settles it.
        let entry = WatchSyncFixtures.pending(.finish(WatchSyncFixtures.finishCommand(workoutID: UUID())), expectedVersion: 1)
        let context = WatchSyncFixtures.context(snapshot: nil)

        #expect(WatchSyncMerge.reconcile(pending: [entry], with: context).count == 1)
    }

    @Test("завершение уходит из очереди по подтверждению commandID")
    func finishLeavesTheQueueOnceAcknowledged() throws {
        let commandID = UUID()
        let entry = WatchSyncFixtures.pending(.finish(WatchSyncFixtures.finishCommand(workoutID: UUID(), commandID: commandID)), expectedVersion: 1)
        let context = WatchSyncFixtures.context(snapshot: nil, appliedCommandIDs: [commandID])

        #expect(WatchSyncMerge.reconcile(pending: [entry], with: context).isEmpty)
    }

    @Test("локальная версия = версия телефона плюс всё, что стоит в очереди по этой тренировке")
    func localVersionCountsTheQueue() throws {
        let workoutID = UUID()
        let context = WatchSyncFixtures.context(snapshot: WatchSyncFixtures.snapshot(workoutID: workoutID, version: 2))
        let pending = [
            WatchSyncFixtures.pending(.logSet(WatchSyncFixtures.logSetCommand(workoutID: workoutID, exerciseID: UUID())), expectedVersion: 3),
            WatchSyncFixtures.pending(.logSet(WatchSyncFixtures.logSetCommand(workoutID: UUID(), exerciseID: UUID())), expectedVersion: 1)
        ]

        #expect(WatchSyncMerge.localVersion(of: workoutID, in: context, pending: pending) == 3)
    }

    @Test("отметка о записи в Здоровье уходит из очереди, когда версия телефона догнала ожидаемую — это такой же +1, как подход")
    func healthRecordedLandsByVersion() throws {
        let workoutID = UUID()
        let entry = WatchSyncFixtures.pending(
            .healthRecorded(WatchSyncFixtures.healthRecordedCommand(workoutID: workoutID)),
            expectedVersion: 3
        )

        let behind = WatchSyncFixtures.context(snapshot: WatchSyncFixtures.snapshot(workoutID: workoutID, version: 2))
        let caughtUp = WatchSyncFixtures.context(snapshot: WatchSyncFixtures.snapshot(workoutID: workoutID, version: 3))

        #expect(WatchSyncMerge.reconcile(pending: [entry], with: behind).count == 1)
        #expect(WatchSyncMerge.reconcile(pending: [entry], with: caughtUp).isEmpty)
    }

    @Test("отметка о записи в Здоровье для завершённой тренировки уходит только по подтверждению commandID")
    func healthRecordedForFinishedWorkoutNeedsAck() throws {
        let workoutID = UUID()
        let command = WatchSyncFixtures.healthRecordedCommand(workoutID: workoutID)
        let entry = WatchSyncFixtures.pending(.healthRecorded(command), expectedVersion: 5)

        #expect(WatchSyncMerge.reconcile(pending: [entry], with: WatchSyncFixtures.context()).count == 1)
        #expect(WatchSyncMerge.reconcile(pending: [entry], with: WatchSyncFixtures.context(appliedCommandIDs: [command.commandID])).isEmpty)
    }
}

@Suite("WatchSyncMerge — порог рекорда веса")
struct WatchSyncMergeRecordWeightTests {
    @Test("подходы из очереди поднимают порог по порядку")
    func queuedSetsRaiseTheBarInOrder() throws {
        let workoutID = UUID()
        let exerciseID = UUID()
        let snapshot = WatchSyncFixtures.snapshot(
            workoutID: workoutID,
            exercises: [WatchSyncFixtures.exerciseInfo(id: exerciseID, recordWeight: 80, tracksRecords: true)]
        )
        let pending = [
            WatchSyncFixtures.pending(.logSet(WatchSyncFixtures.logSetCommand(workoutID: workoutID, exerciseID: exerciseID, weight: 85)), expectedVersion: 1),
            WatchSyncFixtures.pending(.logSet(WatchSyncFixtures.logSetCommand(workoutID: workoutID, exerciseID: exerciseID, weight: 82.5)), expectedVersion: 2),
        ]

        let merged = try #require(WatchSyncMerge.activeSnapshot(in: WatchSyncFixtures.context(snapshot: snapshot), pending: pending))
        let exercise = try #require(merged.exercises.first)

        #expect(exercise.recordWeight == 85)
        #expect(exercise.tracksRecords)
        #expect(!exercise.isWeightRecord(85))
        #expect(exercise.isWeightRecord(87.5))
    }

    @Test("без истории первый подход не рекорд, но задаёт порог следующему")
    func firstSetSetsTheBar() throws {
        let workoutID = UUID()
        let exerciseID = UUID()
        let info = WatchSyncFixtures.exerciseInfo(id: exerciseID, recordWeight: nil, tracksRecords: true)
        let snapshot = WatchSyncFixtures.snapshot(workoutID: workoutID, exercises: [info])
        let pending = [
            WatchSyncFixtures.pending(.logSet(WatchSyncFixtures.logSetCommand(workoutID: workoutID, exerciseID: exerciseID, weight: 60)), expectedVersion: 1),
        ]

        let merged = try #require(WatchSyncMerge.activeSnapshot(in: WatchSyncFixtures.context(snapshot: snapshot), pending: pending))
        let exercise = try #require(merged.exercises.first)

        #expect(!info.isWeightRecord(60))
        #expect(exercise.recordWeight == 60)
        #expect(exercise.isWeightRecord(62.5))
    }

    @Test("подход без веса не рекорд и порог не двигает")
    func bodyweightSetNeitherRecordsNorRaises() throws {
        let workoutID = UUID()
        let exerciseID = UUID()
        let info = WatchSyncFixtures.exerciseInfo(id: exerciseID, recordWeight: 80, tracksRecords: true)
        let snapshot = WatchSyncFixtures.snapshot(workoutID: workoutID, exercises: [info])
        let pending = [
            WatchSyncFixtures.pending(.logSet(WatchSyncFixtures.logSetCommand(workoutID: workoutID, exerciseID: exerciseID, weight: 0)), expectedVersion: 1),
        ]

        let merged = try #require(WatchSyncMerge.activeSnapshot(in: WatchSyncFixtures.context(snapshot: snapshot), pending: pending))

        #expect(!info.isWeightRecord(0))
        #expect(merged.exercises.first?.recordWeight == 80)
    }

    @Test("план, начатый на часах без телефона, несёт порог рекорда")
    func locallyStartedPlanCarriesTheBar() throws {
        let planID = UUID()
        let exerciseID = UUID()
        let plan = WatchSyncFixtures.summary(
            id: planID,
            exercises: [WatchSyncFixtures.exerciseInfo(id: exerciseID, recordWeight: 100, tracksRecords: true)]
        )
        let pending = [
            WatchSyncFixtures.pending(.start(WatchSyncFixtures.startCommand(workoutID: planID)), expectedVersion: 1),
            WatchSyncFixtures.pending(.logSet(WatchSyncFixtures.logSetCommand(workoutID: planID, exerciseID: exerciseID, weight: 105)), expectedVersion: 2),
        ]

        let merged = try #require(WatchSyncMerge.activeSnapshot(in: WatchSyncFixtures.context(plans: [plan]), pending: pending))

        #expect(merged.exercises.first?.recordWeight == 105)
        #expect(merged.exercises.first?.tracksRecords == true)
    }

    @Test("старый телефон без порога: рекордов на часах нет и после подходов из очереди")
    func olderPhoneNeverAnnouncesRecords() throws {
        let workoutID = UUID()
        let exerciseID = UUID()
        let snapshot = WatchSyncFixtures.snapshot(
            workoutID: workoutID,
            exercises: [WatchSyncFixtures.exerciseInfo(id: exerciseID)]
        )
        let pending = [
            WatchSyncFixtures.pending(.logSet(WatchSyncFixtures.logSetCommand(workoutID: workoutID, exerciseID: exerciseID, weight: 60)), expectedVersion: 1),
        ]

        let merged = try #require(WatchSyncMerge.activeSnapshot(in: WatchSyncFixtures.context(snapshot: snapshot), pending: pending))

        #expect(merged.exercises.first?.isWeightRecord(100) == false)
    }
}
