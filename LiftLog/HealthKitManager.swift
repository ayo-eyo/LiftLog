import HealthKit
import os

/// Seam over `HKWorkoutBuilder`'s begin/end/finish lifecycle so `HealthKitManager.save`
/// is testable without touching real HealthKit — neither `HKHealthStore` nor
/// `HKWorkoutBuilder` can be faked directly (both are final system classes), so tests
/// substitute a fake conforming to this protocol instead. A fresh instance backs each
/// `save` call (the default parameter expression below), since a builder is single-use:
/// one begin/end/finish per workout, not a value that's safe to share across calls the
/// way the old `HKHealthStore`-backed seam was.
protocol WorkoutSavingStore {
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus
    func beginCollection(at date: Date) async throws
    func endCollection(at date: Date) async throws
    func finishWorkout() async throws
}

private final class HealthKitWorkoutBuildingStore: WorkoutSavingStore {
    private let healthStore: HKHealthStore
    private let builder: HKWorkoutBuilder

    init(healthStore: HKHealthStore, activityType: HKWorkoutActivityType) {
        self.healthStore = healthStore
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        self.builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: nil)
    }

    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        healthStore.authorizationStatus(for: type)
    }

    func beginCollection(at date: Date) async throws {
        try await builder.beginCollection(at: date)
    }

    func endCollection(at date: Date) async throws {
        try await builder.endCollection(at: date)
    }

    func finishWorkout() async throws {
        _ = try await builder.finishWorkout()
    }
}

enum HealthKitManager {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LiftLog", category: "HealthKit")
    private static let store = HKHealthStore()

    static func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set = [HKQuantityType.workoutType()]
        try? await store.requestAuthorization(toShare: share, read: [])
    }

    // `savingStore` defaults to `nil` and is constructed inside the body rather than as
    // a default-parameter expression: `HealthKitWorkoutBuildingStore.init` and `store`
    // are main-actor-isolated (the project defaults every type to `@MainActor`), and a
    // default-parameter expression evaluates outside the function's own isolation, so
    // building it eagerly there warned about a cross-actor call.
    static func save(_ workout: Workout, to savingStore: WorkoutSavingStore? = nil) async {
        guard let end = workout.completedAt, !workout.sets.isEmpty else { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let savingStore = savingStore ?? HealthKitWorkoutBuildingStore(healthStore: store, activityType: .traditionalStrengthTraining)
        guard savingStore.authorizationStatus(for: .workoutType()) == .sharingAuthorized else { return }

        let start = workout.startedAt ?? workout.date
        do {
            try await savingStore.beginCollection(at: start)
            try await savingStore.endCollection(at: end)
            try await savingStore.finishWorkout()
        } catch {
            logger.error("HealthKit save failed: \(error.localizedDescription)")
        }
    }
}
