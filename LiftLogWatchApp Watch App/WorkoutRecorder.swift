import Foundation
import HealthKit
import os

/// Records the running workout into Health with a live workout session: heart rate,
/// active and basal energy, duration — what the phone's own save can't provide. Follows
/// the merged snapshot (`PhoneSessionManager.snapshot`): a workout appearing starts a
/// session, the workout going away (finished here or on the phone) ends it and saves.
///
/// The decision of *what* to do is `WatchHealthRecording.action` in the shared sync file,
/// so it's covered from `LiftLogTests`; this class only drives HealthKit.
@MainActor
final class WorkoutRecorder: NSObject {
    static let shared = WorkoutRecorder()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LiftLogWatchApp", category: "WorkoutRecorder")
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    /// The LiftLog workout the current session belongs to. Persisted so a session
    /// recovered after the app was killed can be matched back to its workout.
    private var workoutID: UUID? {
        didSet { UserDefaults.standard.set(workoutID?.uuidString, forKey: Self.workoutIDKey) }
    }
    /// A workout that should be recorded as soon as the current session finishes saving —
    /// only one session can run at a time.
    private var pendingStart: (id: UUID, date: Date)?

    /// Called once collection has actually begun for a workout — that is the moment the
    /// phone can safely skip its own save.
    var onRecordingStarted: ((UUID) -> Void)?

    private static let workoutIDKey = "WorkoutRecorder.workoutID"

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [
            .workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
        ]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
        ]
        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
        } catch {
            logger.error("HealthKit authorization failed: \(error.localizedDescription)")
        }
    }

    /// Brings the session in line with the workout the watch currently shows.
    func sync(activeWorkoutID: UUID?, workoutDate: Date?, startedLocally: Bool, isTrusted: Bool, now: Date = Date()) {
        let action = WatchHealthRecording.action(recording: workoutID, active: activeWorkoutID, isTrusted: isTrusted)
        let start: (UUID) -> (id: UUID, date: Date) = { id in
            (id, WatchHealthRecording.collectionStart(workoutDate: workoutDate ?? now, startedLocally: startedLocally, now: now))
        }
        switch action {
        case .none:
            break
        case .start(let id):
            begin(start(id))
        case .end:
            pendingStart = nil
            end()
        case .restart(let id):
            pendingStart = start(id)
            end()
        }
    }

    /// The app was relaunched with a session still running (crash, or the system killed
    /// it) — reattach to it instead of losing the recording.
    func recover() async {
        do {
            guard let session = try await healthStore.recoverActiveWorkoutSession() else { return }
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: session.workoutConfiguration)
            session.delegate = self
            self.session = session
            self.builder = builder
            let storedID = UserDefaults.standard.string(forKey: Self.workoutIDKey).flatMap(UUID.init(uuidString:))
            if let storedID {
                workoutID = storedID
            } else {
                // Nothing to tie it to — a recording no workout will ever claim.
                logger.error("recovered a workout session with no workout ID, ending it")
                session.end()
            }
        } catch {
            logger.error("workout session recovery failed: \(error.localizedDescription)")
        }
    }

    // MARK: Session lifecycle

    private func begin(_ target: (id: UUID, date: Date)) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard session == nil else {
            pendingStart = target
            return
        }
        // Without write access the session would run but save nothing — and reporting it
        // as recorded would make the phone skip the only copy that does get saved.
        guard healthStore.authorizationStatus(for: .workoutType()) == .sharingAuthorized else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let session: HKWorkoutSession
        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        } catch {
            logger.error("could not create workout session: \(error.localizedDescription)")
            return
        }
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session.delegate = self
        self.session = session
        self.builder = builder
        workoutID = target.id

        session.startActivity(with: target.date)
        Task {
            do {
                try await builder.beginCollection(at: target.date)
                try await builder.addMetadata([
                    HKMetadataKeyIndoorWorkout: true,
                    WatchHealthRecording.workoutIDMetadataKey: target.id.uuidString,
                    WatchHealthRecording.recordedOnMetadataKey: WatchHealthRecording.recordedOnWatch,
                ])
                onRecordingStarted?(target.id)
            } catch {
                logger.error("could not begin collection: \(error.localizedDescription)")
                // Collection never started: nothing will be saved, so don't pretend.
                session.end()
            }
        }
    }

    private func end() {
        guard let session else { return }
        if session.state == .ended || session.state == .stopped {
            return
        }
        session.end()
    }

    private func finish(at endDate: Date) async {
        defer {
            session = nil
            builder = nil
            workoutID = nil
            if let next = pendingStart {
                pendingStart = nil
                begin(next)
            }
        }
        guard let builder else { return }
        do {
            try await builder.endCollection(at: endDate)
            _ = try await builder.finishWorkout()
        } catch {
            logger.error("could not save the workout to Health: \(error.localizedDescription)")
        }
    }
}

extension WorkoutRecorder: HKWorkoutSessionDelegate {
    // HealthKit calls these on its own queue; state is main-actor-isolated, so hop.

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended else { return }
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            await self.finish(at: date)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.logger.error("workout session failed: \(error.localizedDescription)")
        }
    }
}
