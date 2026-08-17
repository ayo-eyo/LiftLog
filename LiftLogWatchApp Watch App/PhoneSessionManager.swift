import Foundation
import WatchConnectivity
import Observation
import os

/// Receives the active workout snapshot pushed from the iPhone app and sends
/// set-logging / rest-skip commands back. The watch has no persistence of its
/// own — it's a thin remote control over the phone's SwiftData store.
@Observable
@MainActor
final class PhoneSessionManager: NSObject, WCSessionDelegate {
    static let shared = PhoneSessionManager()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LiftLogWatchApp", category: "PhoneSession")

    var snapshot: WatchWorkoutSnapshot?

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Result of a logSet round-trip. `.confirmed` carries the phone's authoritative
    /// next-set defaults (post-template) straight from the reply, avoiding any race
    /// with the separate `updateApplicationContext` snapshot push. `.queued` means
    /// the phone wasn't reachable — the command was handed to `transferUserInfo` and
    /// will deliver eventually, but we have no fresh defaults to show yet. `.failed`
    /// means it couldn't even be queued.
    enum LogSetResult {
        case confirmed(WatchWorkoutSnapshot.ExerciseInfo)
        case queued
        case failed
    }

    func logSet(exerciseID: UUID, exerciseName: String, weight: Double, reps: Int, completion: @escaping (LogSetResult) -> Void) {
        guard let workoutID = snapshot?.workoutID else {
            completion(.failed)
            return
        }
        let command = WatchLogSetCommand(commandID: UUID(), workoutID: workoutID, exerciseID: exerciseID, exerciseName: exerciseName, weight: weight, reps: reps)
        guard let data = try? JSONEncoder().encode(command) else {
            completion(.failed)
            return
        }
        send(["logSet": data]) { reply in
            guard let reply else {
                completion(.queued)
                return
            }
            if let infoData = reply["exercise"] as? Data,
               let info = try? JSONDecoder().decode(WatchWorkoutSnapshot.ExerciseInfo.self, from: infoData) {
                completion(.confirmed(info))
            } else if (reply["ok"] as? Bool) == true {
                completion(.queued)
            } else {
                completion(.failed)
            }
        }
    }

    func skipRest() {
        send(["skipRest": true])
    }

    /// `completion` receives the phone's reply dictionary, or nil if the message
    /// could only be queued via `transferUserInfo` (no reply is possible there).
    private func send(_ message: [String: Any], completion: (([String: Any]?) -> Void)? = nil) {
        let session = WCSession.default
        guard session.activationState == .activated else {
            completion?(nil)
            return
        }
        if session.isReachable {
            session.sendMessage(message, replyHandler: { reply in
                completion?(reply)
            }) { [weak self] error in
                self?.logger.error("sendMessage failed, falling back to transferUserInfo: \(error.localizedDescription)")
                session.transferUserInfo(message)
                completion?(nil)
            }
        } else {
            session.transferUserInfo(message)
            completion?(nil)
        }
    }

    // MARK: WCSessionDelegate

    // WatchConnectivity calls these on its own delegate queue, not necessarily main —
    // `nonisolated` here, hopping to the main actor for the actual state write, keeps
    // `snapshot` single-threaded on main (the class is `@MainActor`).

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            logger.error("activation failed: \(error.localizedDescription)")
        }
        if let data = session.receivedApplicationContext["data"] as? Data {
            applyContext(data)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["data"] as? Data else { return }
        applyContext(data)
    }

    // `sessionDidBecomeInactive`/`sessionDidDeactivate` exist on `WCSessionDelegate` but
    // are `__WATCHOS_UNAVAILABLE` — implementing them here doesn't compile for this
    // target (they're the iOS-side multi-session-transition callbacks; watchOS has only
    // one paired counterpart, so they don't apply). Only the two methods above are
    // required/relevant on watchOS.

    nonisolated private func applyContext(_ data: Data) {
        // `WatchContext`'s `Decodable` conformance is main-actor-isolated (the project
        // defaults every type to `@MainActor`), so the decode itself has to happen
        // after hopping, not before — decoding here in the `nonisolated` function would
        // warn under Swift 5 and fail to compile under the Swift 6 language mode.
        Task { @MainActor in
            guard let context = try? JSONDecoder().decode(WatchContext.self, from: data) else { return }
            let oldEndDate = self.snapshot?.restEndDate
            let newEndDate = context.snapshot?.restEndDate
            self.snapshot = context.snapshot
            guard oldEndDate != newEndDate else { return }
            if let newEndDate, newEndDate > Date() {
                RestNotificationManager.schedule(endDate: newEndDate, exerciseName: context.snapshot?.restExerciseName)
            } else {
                RestNotificationManager.cancel()
            }
        }
    }
}
