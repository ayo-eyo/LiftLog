import HealthKit
import Combine

final class WorkoutManager: NSObject, ObservableObject {
    let healthStore = HKHealthStore()
    var session: HKWorkoutSession?
    var builder: HKLiveWorkoutBuilder?

    @Published var heartRate: Double = 0
    @Published var isRunning = false

    func requestAuthorization() async {
        let share: Set = [HKQuantityType.workoutType()]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned)
        ]
        try? await healthStore.requestAuthorization(toShare: share, read: read)
    }

    func start() {
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor

        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            builder = session?.associatedWorkoutBuilder()
            builder?.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore, workoutConfiguration: config
            )
            session?.delegate = self
            builder?.delegate = self

            let now = Date()
            session?.startActivity(with: now)
            builder?.beginCollection(withStart: now) { _, _ in }
            isRunning = true
        } catch {
            print("start failed: \(error)")
        }
    }

    func end() {
        session?.end()
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ builder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hrType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(hrType),
              let stats = builder.statistics(for: hrType),
              let bpm = stats.mostRecentQuantity()?
                  .doubleValue(for: .count().unitDivided(by: .minute()))
        else { return }

        DispatchQueue.main.async { self.heartRate = bpm }
    }

    func workoutBuilderDidCollectEvent(_ builder: HKLiveWorkoutBuilder) {}
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ session: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended else { return }
        builder?.endCollection(withEnd: date) { _, _ in
            self.builder?.finishWorkout { _, _ in
                DispatchQueue.main.async { self.isRunning = false }
            }
        }
    }

    func workoutSession(_ session: HKWorkoutSession, didFailWithError error: Error) {
        print("session failed: \(error)")
    }
}
