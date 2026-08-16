import Testing
import HealthKit
import SwiftData
@testable import LiftLog

/// `HKHealthStore` is a final system class, so `HealthKitManager.save` takes a
/// `WorkoutSavingStore` seam instead — this fake stands in for it.
private final class FakeSavingStore: WorkoutSavingStore {
    var authorizationStatusToReturn: HKAuthorizationStatus = .sharingAuthorized
    private(set) var saveCallCount = 0
    var errorToReturn: Error?

    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        authorizationStatusToReturn
    }

    func save(_ object: HKObject, withCompletion completion: @escaping (Bool, Error?) -> Void) {
        saveCallCount += 1
        completion(errorToReturn == nil, errorToReturn)
    }
}

@Suite("HealthKitManager.save")
struct HealthKitManagerTests {
    @Test("не сохраняет тренировку без подходов")
    func skipsEmptyWorkout() throws {
        let store = try TestStore.open()
        let workout = Fixtures.workout(in: store.context)
        // Not `.finish()` (`.now`): `workout.date` is the fixed `Fixtures.epoch`, and a
        // real `.now` end date would make `HKWorkout` reject the sample — its validation
        // caps sample duration at 4 days.
        workout.completedAt = Fixtures.date(offset: 3600)

        let fake = FakeSavingStore()
        HealthKitManager.save(workout, to: fake)

        #expect(fake.saveCallCount == 0)
    }

    @Test("не сохраняет незавершённую тренировку")
    func skipsUnfinishedWorkout() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)
        Fixtures.log([(60, 8)], for: exercise, in: workout, context: store.context)
        // workout.completedAt остаётся nil

        let fake = FakeSavingStore()
        HealthKitManager.save(workout, to: fake)

        #expect(fake.saveCallCount == 0)
    }

    @Test("не сохраняет без разрешения на запись в Health")
    func skipsWhenNotAuthorized() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)
        Fixtures.log([(60, 8)], for: exercise, in: workout, context: store.context)
        // Not `.finish()` (`.now`): `workout.date` is the fixed `Fixtures.epoch`, and a
        // real `.now` end date would make `HKWorkout` reject the sample — its validation
        // caps sample duration at 4 days.
        workout.completedAt = Fixtures.date(offset: 3600)

        let fake = FakeSavingStore()
        fake.authorizationStatusToReturn = .notDetermined
        HealthKitManager.save(workout, to: fake)

        #expect(fake.saveCallCount == 0)
    }

    @Test("сохраняет завершённую тренировку с подходами при наличии разрешения")
    func savesCompletedWorkoutWithSets() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [exercise], in: store.context)
        Fixtures.log([(60, 8)], for: exercise, in: workout, context: store.context)
        // Not `.finish()` (`.now`): `workout.date` is the fixed `Fixtures.epoch`, and a
        // real `.now` end date would make `HKWorkout` reject the sample — its validation
        // caps sample duration at 4 days.
        workout.completedAt = Fixtures.date(offset: 3600)

        let fake = FakeSavingStore()
        HealthKitManager.save(workout, to: fake)

        #expect(fake.saveCallCount == 1)
    }
}
