import Testing
import HealthKit
import SwiftData
@testable import LiftLog

/// `HKHealthStore`/`HKWorkoutBuilder` are final system classes, so
/// `HealthKitManager.save` takes a `WorkoutSavingStore` seam instead — this fake
/// stands in for it.
private final class FakeSavingStore: WorkoutSavingStore {
    var authorizationStatusToReturn: HKAuthorizationStatus = .sharingAuthorized
    private(set) var beginCollectionCallCount = 0
    private(set) var endCollectionCallCount = 0
    private(set) var finishWorkoutCallCount = 0
    private(set) var metadata: [String: Any] = [:]
    var errorToThrow: Error?
    /// Runs inside `finishWorkout` — lets a test land something mid-save.
    var duringFinish: (() -> Void)?

    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        authorizationStatusToReturn
    }

    func beginCollection(at date: Date) async throws {
        beginCollectionCallCount += 1
        if let errorToThrow { throw errorToThrow }
    }

    func addMetadata(_ metadata: [String: Any]) async throws {
        self.metadata.merge(metadata) { _, new in new }
    }

    func endCollection(at date: Date) async throws {
        endCollectionCallCount += 1
        if let errorToThrow { throw errorToThrow }
    }

    func finishWorkout() async throws {
        finishWorkoutCallCount += 1
        if let errorToThrow { throw errorToThrow }
        duringFinish?()
    }
}

private final class FakeDeletingStore: WorkoutDeletingStore {
    private(set) var deletedWorkoutIDs: [UUID] = []

    func deletePhoneWorkouts(liftLogWorkoutID: UUID) async throws {
        deletedWorkoutIDs.append(liftLogWorkoutID)
    }
}

@Suite("HealthKitManager — тренировка, записанная часами")
struct HealthKitManagerWatchRecordingTests {
    @Test("не сохраняет свою копию, если тренировку записали часы")
    func skipsWhenRecordedOnWatch() async throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)
        Fixtures.log([(60, 8)], for: exercise, in: workout, context: store.context)
        workout.completedAt = Fixtures.date(offset: 3600)
        workout.healthRecordedOnWatch = true

        let fake = FakeSavingStore()
        await HealthKitManager.save(workout, to: fake)

        #expect(fake.beginCollectionCallCount == 0)
        #expect(fake.finishWorkoutCallCount == 0)
    }

    @Test("копия телефона помечена ID тренировки и источником — по ним её потом находят для удаления")
    func stampsWorkoutIDAndSource() async throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)
        Fixtures.log([(60, 8)], for: exercise, in: workout, context: store.context)
        workout.completedAt = Fixtures.date(offset: 3600)

        let fake = FakeSavingStore()
        await HealthKitManager.save(workout, to: fake)

        #expect(fake.metadata[WatchHealthRecording.workoutIDMetadataKey] as? String == workout.syncID.uuidString)
        #expect(fake.metadata[WatchHealthRecording.recordedOnMetadataKey] as? String == WatchHealthRecording.recordedOnPhone)
        #expect(fake.metadata[HKMetadataKeyIndoorWorkout] as? Bool == true)
    }

    @Test("отметка с часов, пришедшая во время сохранения, удаляет только что сохранённую копию")
    func deletesCopyWhenWatchReportLandsMidSave() async throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)
        Fixtures.log([(60, 8)], for: exercise, in: workout, context: store.context)
        workout.completedAt = Fixtures.date(offset: 3600)

        let saving = FakeSavingStore()
        saving.duringFinish = { workout.healthRecordedOnWatch = true }
        let deleting = FakeDeletingStore()
        await HealthKitManager.save(workout, to: saving, deletingStore: deleting)

        #expect(saving.finishWorkoutCallCount == 1)
        #expect(deleting.deletedWorkoutIDs == [workout.syncID])
    }

    @Test("обычное сохранение ничего не удаляет")
    func plainSaveDeletesNothing() async throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)
        Fixtures.log([(60, 8)], for: exercise, in: workout, context: store.context)
        workout.completedAt = Fixtures.date(offset: 3600)

        let deleting = FakeDeletingStore()
        await HealthKitManager.save(workout, to: FakeSavingStore(), deletingStore: deleting)

        #expect(deleting.deletedWorkoutIDs.isEmpty)
    }
}

@Suite("HealthKitManager.save")
struct HealthKitManagerTests {
    @Test("не сохраняет тренировку без подходов")
    func skipsEmptyWorkout() async throws {
        let store = try TestStore.open()
        let workout = Fixtures.workout(in: store.context)
        workout.completedAt = Fixtures.date(offset: 3600)

        let fake = FakeSavingStore()
        await HealthKitManager.save(workout, to: fake)

        #expect(fake.finishWorkoutCallCount == 0)
    }

    @Test("не сохраняет незавершённую тренировку")
    func skipsUnfinishedWorkout() async throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)
        Fixtures.log([(60, 8)], for: exercise, in: workout, context: store.context)
        // workout.completedAt остаётся nil

        let fake = FakeSavingStore()
        await HealthKitManager.save(workout, to: fake)

        #expect(fake.finishWorkoutCallCount == 0)
    }

    @Test("не сохраняет без разрешения на запись в Health")
    func skipsWhenNotAuthorized() async throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)
        Fixtures.log([(60, 8)], for: exercise, in: workout, context: store.context)
        workout.completedAt = Fixtures.date(offset: 3600)

        let fake = FakeSavingStore()
        fake.authorizationStatusToReturn = .notDetermined
        await HealthKitManager.save(workout, to: fake)

        #expect(fake.beginCollectionCallCount == 0)
        #expect(fake.finishWorkoutCallCount == 0)
    }

    @Test("сохраняет завершённую тренировку с подходами при наличии разрешения")
    func savesCompletedWorkoutWithSets() async throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)
        Fixtures.log([(60, 8)], for: exercise, in: workout, context: store.context)
        workout.completedAt = Fixtures.date(offset: 3600)

        let fake = FakeSavingStore()
        await HealthKitManager.save(workout, to: fake)

        #expect(fake.beginCollectionCallCount == 1)
        #expect(fake.endCollectionCallCount == 1)
        #expect(fake.finishWorkoutCallCount == 1)
    }

    @Test("ошибка на любом шаге builder'а не падает, только логируется")
    func builderErrorIsSwallowed() async throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)
        Fixtures.log([(60, 8)], for: exercise, in: workout, context: store.context)
        workout.completedAt = Fixtures.date(offset: 3600)

        let fake = FakeSavingStore()
        fake.errorToThrow = NSError(domain: "test", code: 1)
        await HealthKitManager.save(workout, to: fake)

        #expect(fake.beginCollectionCallCount == 1)
        #expect(fake.endCollectionCallCount == 0, "endCollection не должен вызываться после ошибки в beginCollection")
    }
}
