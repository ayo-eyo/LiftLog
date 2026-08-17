import HealthKit
import os

/// Seam over `HKHealthStore` so `HealthKitManager.save` is testable without touching
/// real HealthKit — `HKHealthStore` itself can't be faked (it's a final system class),
/// so tests substitute a fake conforming to this protocol instead.
protocol WorkoutSavingStore {
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus
    func save(_ object: HKObject, withCompletion completion: @escaping @Sendable (Bool, Error?) -> Void)
}

extension HKHealthStore: WorkoutSavingStore {}

enum HealthKitManager {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LiftLog", category: "HealthKit")
    private static let store = HKHealthStore()

    static func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set = [HKQuantityType.workoutType()]
        try? await store.requestAuthorization(toShare: share, read: [])
    }

    static func save(_ workout: Workout, to savingStore: WorkoutSavingStore = store) {
        guard let end = workout.completedAt, !workout.sets.isEmpty else { return }
        guard HKHealthStore.isHealthDataAvailable(),
              savingStore.authorizationStatus(for: .workoutType()) == .sharingAuthorized else { return }

        let hkWorkout = HKWorkout(activityType: .traditionalStrengthTraining, start: workout.startedAt ?? workout.date, end: end)
        savingStore.save(hkWorkout, withCompletion: { success, error in
            if let error {
                logger.error("HealthKit save failed: \(error.localizedDescription)")
            } else if !success {
                logger.error("HealthKit save did not succeed, no error returned")
            }
        })
    }
}
