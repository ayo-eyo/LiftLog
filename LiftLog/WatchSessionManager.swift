import Foundation
import WatchConnectivity
import SwiftData
import os

/// Pushes the active workout to the paired Watch app and applies commands
/// (log a set, skip rest) it sends back. The watch has no SwiftData store of
/// its own — this is the only place that touches the phone's ModelContext
/// on the watch's behalf.
final class WatchSessionManager: NSObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LiftLog", category: "WatchSession")
    private var modelContext: ModelContext?
    private weak var restTimer: RestTimer?
    private var started = false

    private static let restDuration: TimeInterval = 120

    func start(modelContext: ModelContext, restTimer: RestTimer) {
        self.modelContext = modelContext
        self.restTimer = restTimer
        guard !started, WCSession.isSupported() else { return }
        started = true
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func pushSnapshot(for workout: Workout?) {
        guard WCSession.default.activationState == .activated else { return }

        let snapshot: WatchWorkoutSnapshot?
        if let workout, workout.isActive {
            snapshot = WatchWorkoutSnapshot(
                workoutID: workout.syncID,
                exercises: workout.exercises.map { self.exerciseInfo(for: $0, in: workout) },
                restEndDate: restTimer?.endDate,
                restExerciseName: restTimer?.exerciseName
            )
        } else {
            snapshot = nil
        }

        guard let data = try? JSONEncoder().encode(WatchContext(snapshot: snapshot)) else { return }
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

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            logger.error("activation failed: \(error.localizedDescription)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handle(message, reply: replyHandler)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(userInfo, reply: nil)
    }

    private func handle(_ message: [String: Any], reply: (([String: Any]) -> Void)?) {
        guard let context = modelContext else {
            reply?(["ok": false])
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.apply(message, context: context, reply: reply)
        }
    }

    private func apply(_ message: [String: Any], context: ModelContext, reply: (([String: Any]) -> Void)?) {
        if let data = message["logSet"] as? Data,
           let command = try? JSONDecoder().decode(WatchLogSetCommand.self, from: data) {
            guard let info = logSet(command, context: context), let infoData = try? JSONEncoder().encode(info) else {
                reply?(["ok": false])
                return
            }
            reply?(["ok": true, "exercise": infoData])
        } else if message["skipRest"] != nil {
            restTimer?.skip()
            reply?(["ok": true])
        } else {
            reply?(["ok": false])
        }
    }

    private func logSet(_ command: WatchLogSetCommand, context: ModelContext) -> WatchWorkoutSnapshot.ExerciseInfo? {
        let workoutID = command.workoutID
        let exerciseID = command.exerciseID
        guard let workout = try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.syncID == workoutID })).first else {
            logger.error("logSet: workout not found for command from watch")
            return nil
        }
        let exerciseByID = try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.syncID == exerciseID })).first
        guard let exercise = exerciseByID ?? workout.exercises.first(where: { $0.name == command.exerciseName }) else {
            logger.error("logSet: exercise not found for command from watch")
            return nil
        }
        workout.logSet(weight: command.weight, reps: command.reps, for: exercise, context: context)
        restTimer?.start(duration: Self.restDuration, exerciseName: exercise.name)
        pushSnapshot(for: workout)
        return exerciseInfo(for: exercise, in: workout)
    }
}
