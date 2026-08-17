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
    var errorToThrow: Error?

    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        authorizationStatusToReturn
    }

    func beginCollection(at date: Date) async throws {
        beginCollectionCallCount += 1
        if let errorToThrow { throw errorToThrow }
    }

    func endCollection(at date: Date) async throws {
        endCollectionCallCount += 1
        if let errorToThrow { throw errorToThrow }
    }

    func finishWorkout() async throws {
        finishWorkoutCallCount += 1
        if let errorToThrow { throw errorToThrow }
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
