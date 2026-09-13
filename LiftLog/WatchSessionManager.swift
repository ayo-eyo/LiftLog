import Foundation
import WatchConnectivity
import SwiftData
import os

/// Seam over the slice of `WCSession` that `WatchSessionManager.send` needs, so a test
/// can verify the live-push behavior without a real paired watch — see the
/// `create-tests` skill's seam table (`WCSession.default` is called out there by name).
/// `WCSession` already has this exact shape, so it conforms with no extra code.
protocol WatchConnectivitySession: AnyObject {
    var activationState: WCSessionActivationState { get }
    var isReachable: Bool { get }
    func updateApplicationContext(_ applicationContext: [String: Any]) throws
    func sendMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?, errorHandler: ((Error) -> Void)?)
}

extension WCSession: WatchConnectivitySession {}

/// Pushes the active workout and the startable plans to the paired Watch app and
/// applies the commands (log a set, start, finish, skip rest) it sends back. The watch
/// has no SwiftData store of its own — this is the only place that touches the phone's
/// ModelContext on the watch's behalf.
@MainActor
final class WatchSessionManager: NSObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LiftLog", category: "WatchSession")
    /// Only `send`'s own outgoing calls go through this seam — activation and the
    /// delegate callbacks below still talk to `WCSession.default` directly, since tests
    /// exercise those by calling `apply`/`logSet`/`finish` etc. directly rather than
    /// through the real session.
    var session: WatchConnectivitySession = WCSession.default
    private var modelContext: ModelContext?
    private weak var restTimer: RestTimer?
    private var started = false
    private var currentWorkout: Workout?

    /// The most recently computed context, kept even when `WCSession` isn't activated
    /// yet or `updateApplicationContext` fails, so it can be resent once activation
    /// completes instead of being lost until the next unrelated workout change.
    private(set) var lastContext: WatchContext?
    private var hasPushedContext = false

    var lastSnapshot: WatchWorkoutSnapshot? { lastContext?.snapshot }
    var lastPlans: [WatchWorkoutSummary] { lastContext?.plans ?? [] }

    /// Commands already applied, so a redelivery (watch retries after the reply leg of
    /// `sendMessage` fails, having already applied on the phone, or the watch reflushes
    /// its offline queue) doesn't apply the same command twice. Also echoed back in the
    /// pushed context, which is how the watch knows what to drop from that queue —
    /// hence a bounded FIFO that outlives the workout, rather than being cleared when
    /// the workout ends (a queued `finish` has to stay deduplicated after it lands).
    private var appliedCommandIDs: [UUID] = []
    private var appliedCommandIDSet: Set<UUID> = []

    static let restDuration: TimeInterval = RestTimer.defaultDuration
    /// `updateApplicationContext` has a payload limit (~262 KB) and every plan carries
    /// its full exercise list, so the list the watch sees is capped.
    static let planLimit = 20
    /// `.finish` now leaves the watch's queue only on an explicit ack (see
    /// `WatchSyncMerge.hasLanded`), so that ack surviving in this history until the
    /// watch actually sees it matters more than it used to — a generous window costs
    /// little (each ID is 16 bytes).
    static let appliedCommandHistoryLimit = 200

    /// `restTimer` is optional so `LiftLogApp`'s app-delegate can activate the
    /// `WCSession` at process launch — before any view exists to own a `RestTimer` —
    /// and `RootTabView.onAppear` can hand one in afterwards without re-triggering
    /// activation. See technical-notes.md §5.4.
    func start(modelContext: ModelContext, restTimer: RestTimer? = nil) {
        self.modelContext = modelContext
        if let restTimer { self.restTimer = restTimer }
        guard !started, WCSession.isSupported() else { return }
        started = true
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Pushes a context built around an explicitly named active workout. Used where the
    /// store can't answer the question itself — right after `context.delete`, where a
    /// fetch would still return the deleted row, or before the caller's own changes are
    /// saved.
    func pushSnapshot(for workout: Workout?) {
        currentWorkout = workout
        push(snapshot: snapshot(of: workout))
    }

    /// Rebuilds the whole context — active workout *and* plans — from the store. Called
    /// wherever the plan list changes, since those screens don't otherwise think about
    /// the watch.
    func refresh() {
        let active = modelContext.flatMap { activeWorkout(context: $0) }
        currentWorkout = active
        push(snapshot: snapshot(of: active))
    }

    private func push(snapshot: WatchWorkoutSnapshot?) {
        let context = WatchContext(snapshot: snapshot, plans: plans(), appliedCommandIDs: appliedCommandIDs)
        lastContext = context
        hasPushedContext = true
        send(context)
    }

    private func send(_ context: WatchContext) {
        guard session.activationState == .activated,
              let data = try? JSONEncoder().encode(context) else { return }
        do {
            try session.updateApplicationContext(["data": data])
        } catch {
            logger.error("failed to push context (\(data.count) bytes): \(error.localizedDescription)")
        }
        // `updateApplicationContext` is a best-effort background-sync channel — it can
        // sit undelivered for a long while when the watch app is already foreground and
        // active, since nothing about it is timely by design. That leaves a set logged
        // on the phone invisible on an already-open watch screen until the watch app is
        // relaunched. When the watch is actually reachable, also push the same payload
        // as a live message, which delivers immediately; `updateApplicationContext`
        // above still covers the case where it isn't (or the message gets lost).
        if session.isReachable {
            let logger = self.logger
            session.sendMessage([WatchMessageKey.push: data], replyHandler: nil) { error in
                logger.error("live push failed, relying on application context: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Building the context

    private func snapshot(of workout: Workout?) -> WatchWorkoutSnapshot? {
        guard let workout, workout.isActive else { return nil }
        return WatchWorkoutSnapshot(
            workoutID: workout.syncID,
            name: workout.name,
            date: workout.date,
            version: workout.version,
            exercises: workout.orderedExercises.map { self.exerciseInfo(for: $0, in: workout) },
            restEndDate: restTimer?.endDate,
            restExerciseName: restTimer?.exerciseName
        )
    }

    private func plans() -> [WatchWorkoutSummary] {
        guard let modelContext else { return [] }
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.startedAt == nil },
            sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = Self.planLimit
        guard let workouts = try? modelContext.fetch(descriptor) else { return [] }
        // A row deleted but not yet saved still comes back from a fetch — sending it
        // would offer the watch a workout it can never start.
        return workouts.filter { !$0.isDeleted }.map { workout in
            WatchWorkoutSummary(
                id: workout.syncID,
                name: workout.name,
                date: workout.date,
                version: workout.version,
                exercises: workout.orderedExercises.map { self.exerciseInfo(for: $0, in: workout) }
            )
        }
    }

    private func exerciseInfo(for exercise: Exercise, in workout: Workout) -> WatchWorkoutSnapshot.ExerciseInfo {
        let sets = workout.setsFor(exercise)
        let weight = workout.defaultWeight(for: exercise) ?? sets.last?.weight
        let reps = workout.defaultReps(for: exercise) ?? sets.last?.reps
        // The whole plan, not just the next position: offline the watch has to advance
        // through it itself, the way `Workout.plannedItem(for:)` does here.
        let plannedSets = workout.sortedItems
            .filter { $0.exercise?.persistentModelID == exercise.persistentModelID }
            .map { WatchWorkoutSnapshot.PlannedSet(weight: $0.plannedWeight, reps: $0.plannedReps) }
        return WatchWorkoutSnapshot.ExerciseInfo(
            id: exercise.syncID,
            name: exercise.name,
            setsLoggedCount: sets.count,
            weight: weight,
            reps: reps,
            plannedSets: plannedSets
        )
    }

    // MARK: WCSessionDelegate

    // WatchConnectivity calls these on its own delegate queue, not necessarily main.
    // `modelContext`/`restTimer`/the context state are all main-actor-isolated (the
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
            if activationState == .activated, self.hasPushedContext, let context = self.lastContext {
                self.send(context)
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
            reply?([WatchMessageKey.ok: false])
            return
        }
        apply(message, context: context, reply: reply)
    }

    // MARK: Applying commands

    func apply(_ message: [String: Any], context: ModelContext, reply: (([String: Any]) -> Void)?) {
        if let data = message[WatchMessageKey.command] as? Data,
           let command = try? JSONDecoder().decode(WatchCommand.self, from: data) {
            perform(command, context: context, reply: reply)
        } else if let data = message[WatchMessageKey.legacyLogSet] as? Data,
                  let command = try? JSONDecoder().decode(WatchLogSetCommand.self, from: data) {
            // Pre-`command` wire format: a watch build older than this phone build.
            guard let info = logSet(command, context: context), let infoData = try? JSONEncoder().encode(info) else {
                reply?([WatchMessageKey.ok: false])
                return
            }
            saveContext(context)
            reply?([WatchMessageKey.ok: true, "exercise": infoData])
        } else if message[WatchMessageKey.requestContext] != nil {
            // The watch asking for the current state. Rebuilt from the store rather
            // than answered from `lastContext`: what the watch is missing is exactly
            // the changes made while it wasn't listening — including any that happened
            // with this app not running at all, where nothing ever called `refresh`.
            refresh()
            reply?(successReply())
        } else if message[WatchMessageKey.skipRest] != nil {
            restTimer?.skip()
            pushSnapshot(for: currentWorkout)
            reply?(successReply())
        } else {
            reply?([WatchMessageKey.ok: false])
        }
    }

    private func perform(_ command: WatchCommand, context: ModelContext, reply: (([String: Any]) -> Void)?) {
        switch command {
        case .logSet(let logSetCommand):
            guard logSet(logSetCommand, context: context) != nil else {
                reply?([WatchMessageKey.ok: false])
                return
            }
        case .start(let startCommand):
            switch start(startCommand, context: context) {
            case .applied:
                break
            case .conflict(let activeID):
                reply?([WatchMessageKey.ok: false, WatchMessageKey.conflict: activeID.uuidString])
                return
            case .notFound:
                reply?([WatchMessageKey.ok: false])
                return
            }
        case .finish(let finishCommand):
            // `finish` no longer fails outright — an unmatched workoutID falls back to
            // whatever's active, and "nothing to finish" is a successful no-op (see
            // technical-notes.md §5.2) — so there's nothing to guard here.
            finish(finishCommand, context: context)
        }
        saveContext(context)
        reply?(successReply())
    }

    /// One save point for every command applied from the watch. `perform` is reached
    /// after `WCSession` wakes the app in the background, where nothing guarantees the
    /// process survives long enough for SwiftData's autosave to run — see
    /// technical-notes.md §5.1.
    private func saveContext(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            logger.error("не удалось сохранить команду с часов: \(error.localizedDescription)")
        }
    }

    /// The reply carries the freshly pushed context so the watch can reconcile its queue
    /// straight from the round trip, without waiting for the separate
    /// `updateApplicationContext` delivery.
    private func successReply() -> [String: Any] {
        var reply: [String: Any] = [WatchMessageKey.ok: true]
        if let lastContext, let data = try? JSONEncoder().encode(lastContext) {
            reply[WatchMessageKey.context] = data
        }
        return reply
    }

    func logSet(_ command: WatchLogSetCommand, context: ModelContext) -> WatchWorkoutSnapshot.ExerciseInfo? {
        guard let workout = workout(with: command.workoutID, context: context) else {
            logger.error("logSet: workout not found for command from watch")
            return nil
        }
        let exerciseID = command.exerciseID
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
        if !appliedCommandIDSet.contains(command.commandID) {
            workout.logSet(weight: command.weight, reps: command.reps, for: exercise, context: context)
            markApplied(command.commandID)
            restTimer?.start(duration: Self.restDuration, exerciseName: exercise.name)
            pushSnapshot(for: workout)
        }
        return exerciseInfo(for: exercise, in: workout)
    }

    enum StartResult: Equatable {
        case applied
        /// Another workout is already running — only one can be active at a time, and
        /// resolving that is the user's call, not this method's.
        case conflict(UUID)
        case notFound
    }

    func start(_ command: WatchStartWorkoutCommand, context: ModelContext) -> StartResult {
        guard let workout = workout(with: command.workoutID, context: context) else {
            logger.error("start: workout not found for command from watch")
            return .notFound
        }
        if let active = activeWorkout(context: context), active.syncID != workout.syncID {
            return .conflict(active.syncID)
        }
        if !appliedCommandIDSet.contains(command.commandID) {
            // Already started (or already finished) — the command is stale, but it still
            // counts as applied so a redelivery doesn't re-stamp `startedAt`.
            if workout.startedAt == nil {
                workout.start()
            }
            markApplied(command.commandID)
        }
        pushSnapshot(for: workout)
        return .applied
    }

    /// Always returns `true`: a finish from the watch is idempotent by design, per
    /// technical-notes.md §5.2. Only one workout can be active at a time, so a
    /// `workoutID` that doesn't resolve (`syncID` reassigned by
    /// `DataIntegrity.deduplicateSyncIDs`, or a stale watch cache) unambiguously means
    /// "finish whatever's running"; and finishing when nothing is active — the watch
    /// redelivering after it already landed — is a successful no-op, not an error.
    @discardableResult
    func finish(_ command: WatchFinishWorkoutCommand, context: ModelContext) -> Bool {
        var target = workout(with: command.workoutID, context: context)
        if target == nil, let active = activeWorkout(context: context) {
            logger.error("finish: workoutID \(command.workoutID) not found on phone, falling back to the active workout — only one can be active at a time")
            target = active
        }
        guard let target else {
            pushSnapshot(for: nil)
            return true
        }
        if !appliedCommandIDSet.contains(command.commandID) {
            markApplied(command.commandID)
            if target.isActive {
                Workout.complete(target, restTimer: restTimer, context: context, watchSession: self)
                return true
            }
        }
        pushSnapshot(for: nil)
        return true
    }

    // MARK: Lookups

    private func workout(with syncID: UUID, context: ModelContext) -> Workout? {
        try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.syncID == syncID })).first
    }

    private func activeWorkout(context: ModelContext) -> Workout? {
        var descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.startedAt != nil && $0.completedAt == nil })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first { !$0.isDeleted }
    }

    private func markApplied(_ commandID: UUID) {
        appliedCommandIDs.append(commandID)
        appliedCommandIDSet.insert(commandID)
        while appliedCommandIDs.count > Self.appliedCommandHistoryLimit {
            appliedCommandIDSet.remove(appliedCommandIDs.removeFirst())
        }
    }
}
