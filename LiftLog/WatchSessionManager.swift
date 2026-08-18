import Foundation
import WatchConnectivity
import SwiftData
import os

/// Pushes the active workout to the paired Watch app and applies commands
/// (log a set, skip rest) it sends back. The watch has no SwiftData store of
/// its own — this is the only place that touches the phone's ModelContext
/// on the watch's behalf.
@MainActor
final class WatchSessionManager: NSObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LiftLog", category: "WatchSession")
    private var modelContext: ModelContext?
    private weak var restTimer: RestTimer?
    private var started = false
    private var currentWorkout: Workout?

    /// The most recently computed snapshot, kept even when `WCSession` isn't activated
    /// yet or `updateApplicationContext` fails, so it can be resent once activation
    /// completes instead of being lost until the next unrelated workout change.
    private(set) var lastSnapshot: WatchWorkoutSnapshot?
    private var hasPushedSnapshot = false

    /// Commands already applied, so a redelivery (watch retries after the reply leg of
    /// `sendMessage` fails, having already applied on the phone, or `transferUserInfo`
    /// redelivers) doesn't log the same set twice.
    private var appliedCommandIDs = Set<UUID>()

    static let restDuration: TimeInterval = RestTimer.defaultDuration

    func start(modelContext: ModelContext, restTimer: RestTimer) {
        self.modelContext = modelContext
        self.restTimer = restTimer
        guard !started, WCSession.isSupported() else { return }
        started = true
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func pushSnapshot(for workout: Workout?) {
        currentWorkout = workout

        let snapshot: WatchWorkoutSnapshot?
        if let workout, workout.isActive {
            snapshot = WatchWorkoutSnapshot(
                workoutID: workout.syncID,
                exercises: workout.orderedExercises.map { self.exerciseInfo(for: $0, in: workout) },
                restEndDate: restTimer?.endDate,
                restExerciseName: restTimer?.exerciseName
            )
        } else {
            // No active workout left — the dedup set exists only to protect a single
            // in-progress session from a redelivered command, so it has no reason to
            // outlive that session.
            appliedCommandIDs.removeAll()
            snapshot = nil
        }

        lastSnapshot = snapshot
        hasPushedSnapshot = true
        send(snapshot)
    }

    private func send(_ snapshot: WatchWorkoutSnapshot?) {
        guard WCSession.default.activationState == .activated,
              let data = try? JSONEncoder().encode(WatchContext(snapshot: snapshot)) else { return }
        do {
            try WCSession.default.updateApplicationContext(["data": data])
        } catch {
            logger.error("failed to push context: \(error.localizedDescription)")
        }
    }

    private func exerciseInfo(for exercise: Exercise, in workout: Workout) -> WatchWorkoutSnapshot.ExerciseInfo {
        let sets = workout.setsFor(exercise)
        let weight = workout.defaultWeight(for: exercise) ?? sets.last?.weight
        let reps = workout.defaultReps(for: exercise) ?? sets.last?.reps
        return WatchWorkoutSnapshot.ExerciseInfo(
            id: exercise.syncID,
            name: exercise.name,
            setsLoggedCount: sets.count,
            weight: weight,
            reps: reps
        )
    }

    // MARK: WCSessionDelegate

    // WatchConnectivity calls these on its own delegate queue, not necessarily main.
    // `modelContext`/`restTimer`/the snapshot state are all main-actor-isolated (the
    // class is `@MainActor`), so each callback is `nonisolated` and hops explicitly —
    // that keeps every read/write of that state on one thread instead of racing the
    // views that write it from `onAppear`/`pushSnapshot`.

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            logger.error("activation failed: \(error.localizedDescription)")
        }
        Task { @MainActor in
            // `pushSnapshot` may have run (e.g. from `ActiveWorkoutView.onAppear`) before
            // activation finished and silently dropped the send — resend it now so the
            // watch isn't stuck waiting for the next unrelated workout change.
            if activationState == .activated, self.hasPushedSnapshot {
                self.send(self.lastSnapshot)
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            self.handle(message, reply: replyHandler)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            self.handle(userInfo, reply: nil)
        }
    }

    private func handle(_ message: [String: Any], reply: (([String: Any]) -> Void)?) {
        guard let context = modelContext else {
            reply?(["ok": false])
            return
        }
        apply(message, context: context, reply: reply)
    }

    func apply(_ message: [String: Any], context: ModelContext, reply: (([String: Any]) -> Void)?) {
        if let data = message["logSet"] as? Data,
           let command = try? JSONDecoder().decode(WatchLogSetCommand.self, from: data) {
            guard let info = logSet(command, context: context), let infoData = try? JSONEncoder().encode(info) else {
                reply?(["ok": false])
                return
            }
            reply?(["ok": true, "exercise": infoData])
        } else if message["skipRest"] != nil {
            restTimer?.skip()
            pushSnapshot(for: currentWorkout)
            reply?(["ok": true])
        } else {
            reply?(["ok": false])
        }
    }

    func logSet(_ command: WatchLogSetCommand, context: ModelContext) -> WatchWorkoutSnapshot.ExerciseInfo? {
        let workoutID = command.workoutID
        let exerciseID = command.exerciseID
        guard let workout = try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.syncID == workoutID })).first else {
            logger.error("logSet: workout not found for command from watch")
            return nil
        }
        let exercise: Exercise?
        if let byID = try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.syncID == exerciseID })).first {
            exercise = byID
        } else if let byName = workout.orderedExercises.first(where: { $0.name == command.exerciseName }) {
            logger.error("logSet: syncID \(exerciseID) not found, falling back to name match '\(command.exerciseName)' — exercise names aren't unique, this can log to the wrong exercise")
            exercise = byName
        } else {
            exercise = nil
        }
        guard let exercise else {
            logger.error("logSet: exercise not found for command from watch")
            return nil
        }
        if !appliedCommandIDs.contains(command.commandID) {
            workout.logSet(weight: command.weight, reps: command.reps, for: exercise, context: context)
            appliedCommandIDs.insert(command.commandID)
            restTimer?.start(duration: Self.restDuration, exerciseName: exercise.name)
            pushSnapshot(for: workout)
        }
        return exerciseInfo(for: exercise, in: workout)
    }
}
