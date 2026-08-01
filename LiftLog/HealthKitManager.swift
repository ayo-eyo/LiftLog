import HealthKit

enum HealthKitManager {
    private static let store = HKHealthStore()

    static func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set = [HKQuantityType.workoutType()]
        try? await store.requestAuthorization(toShare: share, read: [])
    }

    static func save(_ workout: Workout) {
        guard let end = workout.completedAt else { return }
        let hkWorkout = HKWorkout(activityType: .traditionalStrengthTraining, start: workout.date, end: end)
        store.save(hkWorkout) { _, _ in }
    }
}
