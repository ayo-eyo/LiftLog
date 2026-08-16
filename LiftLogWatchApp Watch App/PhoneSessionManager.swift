import Foundation
import WatchConnectivity
import Combine
import os

/// Receives the active workout snapshot pushed from the iPhone app and sends
/// set-logging / rest-skip commands back. The watch has no persistence of its
/// own — it's a thin remote control over the phone's SwiftData store.
final class PhoneSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = PhoneSessionManager()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LiftLogWatchApp", category: "PhoneSession")

    @Published var snapshot: WatchWorkoutSnapshot?

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

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            logger.error("activation failed: \(error.localizedDescription)")
        }
        if let data = session.receivedApplicationContext["data"] as? Data {
            applyContext(data)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["data"] as? Data else { return }
        applyContext(data)
    }

    private func applyContext(_ data: Data) {
        guard let context = try? JSONDecoder().decode(WatchContext.self, from: data) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
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
