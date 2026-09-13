import Foundation
import WatchConnectivity
import Observation
import os

/// Mirrors the iPhone's workouts and sends commands back. The watch still has no
/// persistence of the workouts themselves — but it does own an offline queue: commands
/// are held locally when the phone isn't reachable and flushed, in order, once it is.
///
/// What the UI reads (`snapshot`, `plans`) is the phone's last context with that queue
/// folded in (`WatchSyncMerge`), so a set logged with the phone in a locker shows up
/// immediately and doesn't disappear when a stale context arrives.
@Observable
@MainActor
final class PhoneSessionManager: NSObject, WCSessionDelegate {
    static let shared = PhoneSessionManager()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LiftLogWatchApp", category: "PhoneSession")
    @ObservationIgnored private let store: PendingCommandStore

    /// What the phone last told us.
    private(set) var context: WatchContext?
    /// Commands the phone hasn't confirmed applying yet.
    private(set) var pending: [WatchPendingCommand] = []
    /// syncID of the workout already running on the phone, when it refused a queued
    /// `start`. Blocks the queue until the user resolves it — everything behind the
    /// start belongs to a workout the phone doesn't consider started.
    private(set) var startConflict: UUID?
    /// Set when the phone rejected a command outright (the workout or exercise is gone
    /// on its side). Surfaced once and cleared by the UI.
    var lastError: String?

    @ObservationIgnored private var isFlushing = false
    /// Commands already handed to `transferUserInfo` on the way to the background, so a
    /// second backgrounding doesn't queue them a second time.
    @ObservationIgnored private var handedOffCommandIDs: Set<UUID> = []

    // Built inside the body rather than as a default-parameter expression: a default
    // argument evaluates outside the initializer's own isolation, and
    // `PendingCommandStore.init` is main-actor-isolated (the project defaults every type
    // to `@MainActor`).
    init(store: PendingCommandStore? = nil) {
        self.store = store ?? PendingCommandStore()
        super.init()
        pending = self.store.load()
    }

    // MARK: What the UI reads

    /// The active workout, phone state plus local queue.
    var snapshot: WatchWorkoutSnapshot? {
        WatchSyncMerge.activeSnapshot(in: context, pending: pending)
    }

    /// Startable plans, minus one already started locally.
    var plans: [WatchWorkoutSummary] {
        WatchSyncMerge.plans(in: context, pending: pending)
    }

    var unsentCount: Int { pending.count }

    /// Whether the active workout is one this watch started while offline.
    var hasUnsentStart: Bool { WatchSyncMerge.locallyStartedWorkoutID(in: pending) != nil }

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: Commands

    func logSet(exerciseID: UUID, exerciseName: String, weight: Double, reps: Int) {
        guard let workoutID = snapshot?.workoutID else { return }
        enqueue(.logSet(WatchLogSetCommand(
            commandID: UUID(),
            workoutID: workoutID,
            exerciseID: exerciseID,
            exerciseName: exerciseName,
            weight: weight,
            reps: reps
        )))
    }

    func startWorkout(_ plan: WatchWorkoutSummary) {
        guard snapshot == nil else { return }
        enqueue(.start(WatchStartWorkoutCommand(commandID: UUID(), workoutID: plan.id)))
    }

    func finishWorkout() {
        guard let workoutID = snapshot?.workoutID else { return }
        enqueue(.finish(WatchFinishWorkoutCommand(commandID: UUID(), workoutID: workoutID)))
    }

    /// Asks the phone for its current context. The phone only pushes when *it* notices
    /// a change, so a push lost on the way — or a plan created while this app wasn't
    /// listening — would otherwise leave this screen on a stale list indefinitely, with
    /// no way for the user to force an update. Live-only, like `skipRest`: when the
    /// phone isn't reachable there's nothing to ask, and `updateApplicationContext`
    /// brings the state along the moment it is.
    ///
    /// `sendMessage` also wakes the phone app in the background if it isn't running, so
    /// this works with the phone in a pocket, screen off.
    func requestContext() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage([WatchMessageKey.requestContext: true]) { [weak self] reply in
            Task { @MainActor in
                guard let data = reply[WatchMessageKey.context] as? Data else { return }
                self?.apply(contextData: data)
            }
        } errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.logger.error("requestContext failed: \(error.localizedDescription)")
            }
        }
    }

    /// Live-only: skipping rest after the fact is meaningless, so it never queues.
    func skipRest() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage([WatchMessageKey.skipRest: true], replyHandler: nil) { [weak self] error in
            Task { @MainActor in
                self?.logger.error("skipRest failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Conflict resolution

    func retryAfterConflict() {
        startConflict = nil
        flush()
    }

    /// Throws away the queued start and everything queued into that workout — the only
    /// way out when the phone is running a different workout and the user picks this
    /// one to lose.
    func cancelQueuedStart() {
        guard let workoutID = WatchSyncMerge.locallyStartedWorkoutID(in: pending) else {
            startConflict = nil
            return
        }
        pending.removeAll { $0.workoutID == workoutID }
        store.save(pending)
        startConflict = nil
        flush()
    }

    /// Sets queued into the workout whose start is stuck — what `cancelQueuedStart()`
    /// would discard.
    var queuedSetCountForConflict: Int {
        guard let workoutID = WatchSyncMerge.locallyStartedWorkoutID(in: pending) else { return 0 }
        return pending.filter { entry in
            guard entry.workoutID == workoutID, case .logSet = entry.command else { return false }
            return true
        }.count
    }

    // MARK: Queue

    private func enqueue(_ command: WatchCommand) {
        let expectedVersion = WatchSyncMerge.localVersion(of: command.workoutID, in: context, pending: pending) + 1
        pending.append(WatchPendingCommand(command: command, expectedVersion: expectedVersion, queuedAt: Date()))
        store.save(pending)
        flush()
    }

    func flush() {
        guard !isFlushing, !pending.isEmpty, startConflict == nil else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        isFlushing = true
        sendNext()
    }

    /// One command at a time, waiting for each reply: order matters, since a `start` has
    /// to be applied before the sets logged into it.
    private func sendNext() {
        guard let entry = pending.first else {
            isFlushing = false
            return
        }
        guard let data = try? JSONEncoder().encode(entry.command) else {
            // Unencodable command would wedge the queue forever.
            logger.error("dropping unencodable queued command")
            drop(entry)
            sendNext()
            return
        }
        let session = WCSession.default
        guard session.isReachable else {
            isFlushing = false
            return
        }
        session.sendMessage([WatchMessageKey.command: data]) { [weak self] reply in
            Task { @MainActor in
                self?.handle(reply: reply, for: entry)
            }
        } errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.logger.error("sendMessage failed, keeping command queued: \(error.localizedDescription)")
                self?.isFlushing = false
            }
        }
    }

    private func handle(reply: [String: Any], for entry: WatchPendingCommand) {
        if let conflict = reply[WatchMessageKey.conflict] as? String, let activeID = UUID(uuidString: conflict) {
            startConflict = activeID
            isFlushing = false
            return
        }
        if (reply[WatchMessageKey.ok] as? Bool) == true {
            drop(entry)
        } else {
            // The phone couldn't apply it at all (workout or exercise gone on its side).
            // Retrying would block everything queued behind it, so it goes — loudly.
            logger.error("phone rejected a queued command, dropping it")
            lastError = "Телефон не принял часть данных"
            drop(entry)
        }
        if let data = reply[WatchMessageKey.context] as? Data {
            apply(contextData: data)
        }
        sendNext()
    }

    private func drop(_ entry: WatchPendingCommand) {
        pending.removeAll { $0.id == entry.id }
        handedOffCommandIDs.remove(entry.id)
        store.save(pending)
    }

    /// Called on the way to the background: whatever is still queued is handed to
    /// `transferUserInfo` so the system delivers it even though this app won't be
    /// running. Entries stay in the queue until the phone acknowledges them — a double
    /// delivery is harmless, the phone deduplicates by `commandID`.
    func handOffToSystemDelivery() {
        guard startConflict == nil else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        for entry in pending where !handedOffCommandIDs.contains(entry.id) {
            guard let data = try? JSONEncoder().encode(entry.command) else { continue }
            session.transferUserInfo([WatchMessageKey.command: data])
            handedOffCommandIDs.insert(entry.id)
        }
    }

    // MARK: WCSessionDelegate

    // WatchConnectivity calls these on its own delegate queue, not necessarily main —
    // `nonisolated` here, hopping to the main actor for the actual state write, keeps
    // the context and the queue single-threaded on main (the class is `@MainActor`).

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            logger.error("activation failed: \(error.localizedDescription)")
        }
        if let data = session.receivedApplicationContext["data"] as? Data {
            applyOnMain(contextData: data)
        }
        Task { @MainActor in
            self.flush()
            // `receivedApplicationContext` is whatever was last delivered — it can be
            // days old, and it's the only thing this app has until the phone next
            // decides to push. Ask for the current state instead of trusting it.
            self.requestContext()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["data"] as? Data else { return }
        applyOnMain(contextData: data)
    }

    /// The live counterpart to `didReceiveApplicationContext` — a `WatchContext` the
    /// phone pushed via `sendMessage` because the watch was reachable, so an
    /// already-open screen updates immediately instead of waiting for
    /// `updateApplicationContext`'s best-effort delivery (see
    /// `WatchSessionManager.send` on the phone).
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // `WatchMessageKey` is main-actor-isolated (the project defaults every type to
        // `@MainActor`), so the key lookup itself has to happen after hopping, same
        // reasoning as `apply(contextData:)`'s decode below.
        Task { @MainActor in
            guard let data = message[WatchMessageKey.push] as? Data else { return }
            self.apply(contextData: data)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.flush()
            // Back in range: the phone may have changed the plan list while it was out
            // of it, and nothing about that change will be re-pushed on its own.
            self.requestContext()
        }
    }

    // `sessionDidBecomeInactive`/`sessionDidDeactivate` exist on `WCSessionDelegate` but
    // are `__WATCHOS_UNAVAILABLE` — implementing them here doesn't compile for this
    // target (they're the iOS-side multi-session-transition callbacks; watchOS has only
    // one paired counterpart, so they don't apply).

    nonisolated private func applyOnMain(contextData data: Data) {
        // `WatchContext`'s `Decodable` conformance is main-actor-isolated (the project
        // defaults every type to `@MainActor`), so the decode itself has to happen
        // after hopping, not before — decoding here in the `nonisolated` function would
        // warn under Swift 5 and fail to compile under the Swift 6 language mode.
        Task { @MainActor in
            self.apply(contextData: data)
        }
    }

    private func apply(contextData data: Data) {
        guard let decoded = try? JSONDecoder().decode(WatchContext.self, from: data) else {
            // Nothing else changes here, so the screen keeps showing the last context
            // that *did* decode — a stale list with no visible cause. Leave a trace.
            logger.error("не удалось декодировать контекст с телефона (\(data.count) байт), экран остаётся на прошлом состоянии")
            return
        }
        let oldEndDate = context?.snapshot?.restEndDate
        context = decoded
        // Drop everything the phone confirmed applying before the UI reads the merged
        // state, or the same sets would be counted twice.
        pending = WatchSyncMerge.reconcile(pending: pending, with: decoded)
        store.save(pending)
        if pending.isEmpty { handedOffCommandIDs.removeAll() }

        let newEndDate = decoded.snapshot?.restEndDate
        if oldEndDate != newEndDate {
            if let newEndDate, newEndDate > Date() {
                RestNotificationManager.schedule(endDate: newEndDate, exerciseName: decoded.snapshot?.restExerciseName)
            } else {
                RestNotificationManager.cancel()
            }
        }
        flush()
    }
}
