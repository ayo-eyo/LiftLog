import HealthKit
import WatchConnectivity
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
    func addMetadata(_ metadata: [String: Any]) async throws
    func endCollection(at date: Date) async throws
    func finishWorkout() async throws
}

/// Seam over deleting the phone's own copy of a workout from Health, same reasoning as
/// `WorkoutSavingStore`.
protocol WorkoutDeletingStore {
    func deletePhoneWorkouts(liftLogWorkoutID: UUID) async throws
}

private final class HealthKitWorkoutBuildingStore: WorkoutSavingStore {
    private let healthStore: HKHealthStore
    private let builder: HKWorkoutBuilder

    init(healthStore: HKHealthStore, activityType: HKWorkoutActivityType) {
        self.healthStore = healthStore
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        configuration.locationType = .indoor
        self.builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: nil)
    }

    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        healthStore.authorizationStatus(for: type)
    }

    func beginCollection(at date: Date) async throws {
        try await builder.beginCollection(at: date)
    }

    func addMetadata(_ metadata: [String: Any]) async throws {
        try await builder.addMetadata(metadata)
    }

    func endCollection(at date: Date) async throws {
        try await builder.endCollection(at: date)
    }

    func finishWorkout() async throws {
        _ = try await builder.finishWorkout()
    }
}

private final class HealthKitWorkoutDeletingStore: WorkoutDeletingStore {
    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
    }

    func deletePhoneWorkouts(liftLogWorkoutID: UUID) async throws {
        // Matched on *both* the workout ID and "recorded on the phone": whether the watch
        // app counts as a separate `HKSource` from this one isn't something to bet the
        // watch's full recording on.
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: HKSource.default()),
            HKQuery.predicateForObjects(
                withMetadataKey: WatchHealthRecording.workoutIDMetadataKey,
                allowedValues: [liftLogWorkoutID.uuidString]
            ),
            HKQuery.predicateForObjects(
                withMetadataKey: WatchHealthRecording.recordedOnMetadataKey,
                allowedValues: [WatchHealthRecording.recordedOnPhone]
            ),
        ])
        _ = try await healthStore.deleteObjects(of: .workoutType(), predicate: predicate)
    }
}

/// The phone's side of Health. Heart rate and energy only exist when the watch records
/// the workout with a live session (`WorkoutRecorder` in the watch target); what the
/// phone saves here is the fallback for a workout done without the watch — start, end,
/// type — and it steps aside whenever the watch reports it recorded the workout itself.
enum HealthKitManager {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LiftLog", category: "HealthKit")
    private static let store = HKHealthStore()

    static func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set = [HKQuantityType.workoutType()]
        try? await store.requestAuthorization(toShare: share, read: [])
    }

    /// Launches the watch app into its workout session when a workout starts on the
    /// phone — without this the watch only records if the user happens to open the app.
    /// A no-op with no paired watch or no watch app installed.
    static func startWatchWorkout() async {
        guard HKHealthStore.isHealthDataAvailable(), WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        do {
            try await store.startWatchApp(toHandle: configuration)
        } catch {
            logger.error("не удалось запустить тренировку на часах: \(error.localizedDescription)")
        }
    }

    /// What the phone's fallback workout carries besides its dates: enough to find it
    /// again (`deletePhoneCopy`) once the watch turns out to have recorded the same one.
    static func phoneMetadata(for workout: Workout) -> [String: Any] {
        [
            HKMetadataKeyIndoorWorkout: true,
            WatchHealthRecording.workoutIDMetadataKey: workout.syncID.uuidString,
            WatchHealthRecording.recordedOnMetadataKey: WatchHealthRecording.recordedOnPhone,
        ]
    }

    // `savingStore` defaults to `nil` and is constructed inside the body rather than as
    // a default-parameter expression: `HealthKitWorkoutBuildingStore.init` and `store`
    // are main-actor-isolated (the project defaults every type to `@MainActor`), and a
    // default-parameter expression evaluates outside the function's own isolation, so
    // building it eagerly there warned about a cross-actor call.
    static func save(_ workout: Workout, to savingStore: WorkoutSavingStore? = nil, deletingStore: WorkoutDeletingStore? = nil) async {
        guard let end = workout.completedAt, !workout.sets.isEmpty else { return }
        // The watch's recording has heart rate and energy; a second, bare workout over the
        // same interval would only double the entry in Health.
        guard !workout.healthRecordedOnWatch else { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let savingStore = savingStore ?? HealthKitWorkoutBuildingStore(healthStore: store, activityType: .traditionalStrengthTraining)
        guard savingStore.authorizationStatus(for: .workoutType()) == .sharingAuthorized else { return }

        let start = workout.startedAt ?? workout.date
        do {
            try await savingStore.beginCollection(at: start)
            try await savingStore.addMetadata(phoneMetadata(for: workout))
            try await savingStore.endCollection(at: end)
            try await savingStore.finishWorkout()
        } catch {
            logger.error("HealthKit save failed: \(error.localizedDescription)")
            return
        }
        // The watch's report can land while the save above was in flight — too late for
        // the guard at the top, too early for `WatchSessionManager.healthRecorded` to find
        // anything to delete. Checked again now that the copy exists.
        if workout.healthRecordedOnWatch {
            await deletePhoneCopy(of: workout.syncID, from: deletingStore)
        }
    }

    /// Removes the fallback workout this phone saved for `syncID` — called once the watch
    /// reports it recorded the same workout with heart rate and energy.
    static func deletePhoneCopy(of syncID: UUID, from deletingStore: WorkoutDeletingStore? = nil) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let deletingStore = deletingStore ?? HealthKitWorkoutDeletingStore(healthStore: store)
        do {
            try await deletingStore.deletePhoneWorkouts(liftLogWorkoutID: syncID)
        } catch {
            logger.error("не удалось удалить копию тренировки с телефона: \(error.localizedDescription)")
        }
    }
}
