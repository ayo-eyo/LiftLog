import Foundation

/// Wire format exchanged over WatchConnectivity between the iPhone and the Watch app.
/// Kept as a plain Codable DTO (not the SwiftData models themselves) since the watch
/// has no SwiftData store of its own — it only mirrors what the phone sends.
///
/// This file exists verbatim in both targets (`LiftLog/` and `LiftLogWatchApp Watch App/`);
/// `Scripts/check-watch-sync-parity.sh` fails if the copies drift. `WatchSyncMerge` at the
/// bottom lives here for the same reason: the watch target has no test target of its own,
/// so the offline-queue logic is written as pure functions in the shared file and covered
/// from `LiftLogTests` against the iOS target's copy.
struct WatchContext: Codable {
    let snapshot: WatchWorkoutSnapshot?
    /// Workouts that haven't been started yet, so the watch can start one itself.
    /// Capped on the phone side — `updateApplicationContext` has a payload limit.
    let plans: [WatchWorkoutSummary]
    /// Recently applied command IDs, echoed back so the watch can drop exactly those
    /// from its pending queue. Bounded, so `WatchSyncMerge` also falls back to the
    /// version rule for anything that aged out of the window.
    let appliedCommandIDs: [UUID]

    init(snapshot: WatchWorkoutSnapshot?, plans: [WatchWorkoutSummary] = [], appliedCommandIDs: [UUID] = []) {
        self.snapshot = snapshot
        self.plans = plans
        self.appliedCommandIDs = appliedCommandIDs
    }

    // Hand-written so a watch build older than the phone build still decodes a context
    // carrying the newer keys as "no plans, no acks" instead of failing the decode
    // outright and showing "no active workout" forever.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        snapshot = try container.decodeIfPresent(WatchWorkoutSnapshot.self, forKey: .snapshot)
        plans = try container.decodeIfPresent([WatchWorkoutSummary].self, forKey: .plans) ?? []
        appliedCommandIDs = try container.decodeIfPresent([UUID].self, forKey: .appliedCommandIDs) ?? []
    }
}

struct WatchWorkoutSnapshot: Codable {
    /// One planned position: the plan for a single set. `Workout.plannedItem(for:)` on
    /// the phone matches the N-th logged set to the N-th planned position — the watch
    /// needs the whole list to reproduce that offline, when the phone isn't there to
    /// compute the next set's defaults.
    struct PlannedSet: Codable {
        let weight: Double?
        let reps: Int?
    }

    struct ExerciseInfo: Codable, Identifiable {
        let id: UUID
        let name: String
        let setsLoggedCount: Int
        /// Defaults for the *next* set, as computed by the phone.
        let weight: Double?
        let reps: Int?
        let plannedSets: [PlannedSet]
    }

    let workoutID: UUID
    let name: String
    let date: Date
    /// Bumped by one on every change to the workout's contents (see `Workout.bumpVersion`).
    /// Monotonic, so "greater version wins" is a meaningful rule for the watch.
    let version: Int
    let exercises: [ExerciseInfo]
    let restEndDate: Date?
    let restExerciseName: String?
}

/// A workout the watch can list and start, but which isn't running yet. Carries the
/// full plan (not just names) so the watch can start it and log into it with no phone
/// in range.
struct WatchWorkoutSummary: Codable, Identifiable {
    let id: UUID
    let name: String
    let date: Date
    let version: Int
    let exercises: [WatchWorkoutSnapshot.ExerciseInfo]
}

// MARK: - Set counters (FR-1)
//
// Derived from `plannedSets`/`setsLoggedCount`, which the wire format already carries —
// no new field, so a watch build older than these extensions still decodes everything.
// Mirrors `Workout.plannedSetCount`/`loggedSetCount`/`remainingSetCount`/
// `isSetPlanFulfilled(for:)` on the phone; see the parity test (T-17 in tests.md) for
// why the two copies of this logic have to move in lockstep.
extension WatchWorkoutSnapshot.ExerciseInfo {
    var plannedSetCount: Int { plannedSets.count }
    /// Sets beyond the plan don't push this negative — see `Workout.remainingSetCount`.
    var remainingSetCount: Int { max(0, plannedSets.count - setsLoggedCount) }
    /// An exercise with no plan is never "fulfilled" — there's nothing to fulfill.
    var isSetPlanFulfilled: Bool { !plannedSets.isEmpty && setsLoggedCount >= plannedSets.count }
}

extension WatchWorkoutSnapshot {
    /// FR-2's auto-advance rule, evaluated over the merged (phone + offline queue)
    /// exercise list so it works with no phone in range. Kept in exact lockstep with
    /// `Workout.nextUnfulfilledExercise(after:)` — see the parity test.
    func nextUnfulfilledExercise(after exerciseID: UUID) -> ExerciseInfo? {
        let candidates = exercises.filter { candidate in
            candidate.id != exerciseID && candidate.plannedSetCount > 0 && candidate.remainingSetCount > 0
        }
        guard !candidates.isEmpty else { return nil }
        guard let currentIndex = exercises.firstIndex(where: { $0.id == exerciseID }) else {
            return candidates.first
        }
        // `candidates` keeps `exercises`' relative order (`filter` preserves order), so
        // the first one whose position in `exercises` is past `currentIndex` is the
        // nearest candidate forward; wrap to the first candidate otherwise.
        if let forward = candidates.first(where: { candidate in
            guard let index = exercises.firstIndex(where: { $0.id == candidate.id }) else { return false }
            return index > currentIndex
        }) {
            return forward
        }
        return candidates.first
    }
}

// MARK: - Watch → phone

struct WatchLogSetCommand: Codable {
    /// Identifies this specific command so a redelivery (watch retries after
    /// `sendMessage` fails on the *reply* leg, having already applied on the phone,
    /// or `transferUserInfo` redelivers) doesn't log the same set twice.
    let commandID: UUID
    let workoutID: UUID
    let exerciseID: UUID
    /// Fallback match if `exerciseID` no longer resolves (e.g. the phone
    /// reassigned syncIDs after the watch cached an older snapshot).
    let exerciseName: String
    let weight: Double
    let reps: Int
}

struct WatchStartWorkoutCommand: Codable {
    let commandID: UUID
    let workoutID: UUID
}

struct WatchFinishWorkoutCommand: Codable {
    let commandID: UUID
    let workoutID: UUID
}

/// One envelope for every mutating command, so the watch can keep them in a single
/// ordered queue while offline — order matters (`start` has to land before the sets
/// logged into it).
enum WatchCommand: Codable {
    case logSet(WatchLogSetCommand)
    case start(WatchStartWorkoutCommand)
    case finish(WatchFinishWorkoutCommand)

    var commandID: UUID {
        switch self {
        case .logSet(let command): command.commandID
        case .start(let command): command.commandID
        case .finish(let command): command.commandID
        }
    }

    var workoutID: UUID {
        switch self {
        case .logSet(let command): command.workoutID
        case .start(let command): command.workoutID
        case .finish(let command): command.workoutID
        }
    }
}

/// A queued command plus the version the workout is expected to reach once the phone
/// applies it. The expectation is the watch's half of the "sync by the greater version"
/// rule; only `command` ever goes on the wire.
struct WatchPendingCommand: Codable, Identifiable {
    let command: WatchCommand
    let expectedVersion: Int
    /// When the watch queued it — what "this has been waiting too long" is measured
    /// against. Only used locally; the phone never sees it.
    let queuedAt: Date

    var id: UUID { command.commandID }
    var workoutID: UUID { command.workoutID }

    init(command: WatchCommand, expectedVersion: Int, queuedAt: Date) {
        self.command = command
        self.expectedVersion = expectedVersion
        self.queuedAt = queuedAt
    }

    // Lenient about `queuedAt`: the queue is read back from disk after an app update,
    // and a queue written by a build without this field must not be thrown away — that
    // would silently drop sets the user logged offline.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(WatchCommand.self, forKey: .command)
        expectedVersion = try container.decode(Int.self, forKey: .expectedVersion)
        queuedAt = try container.decodeIfPresent(Date.self, forKey: .queuedAt) ?? Date()
    }
}

/// Keys of the `[String: Any]` dictionaries `sendMessage`/`transferUserInfo` carry.
enum WatchMessageKey {
    static let command = "command"
    /// Pre-`command` wire format, still accepted by the phone so an older watch build
    /// keeps working after the phone updates.
    static let legacyLogSet = "logSet"
    /// Live-only: skipping rest after the fact is meaningless, so it never queues.
    static let skipRest = "skipRest"

    static let ok = "ok"
    static let context = "context"
    /// syncID of the workout already running on the phone, when a `start` is refused.
    static let conflict = "conflict"
}

// MARK: - Merge

/// The watch's view of the world = what the phone last sent, plus whatever is still
/// sitting in the local queue. Pure functions over values so they can be tested from
/// the iOS test target (see the file header).
enum WatchSyncMerge {
    /// Commands the phone has demonstrably applied, dropped from the queue.
    ///
    /// The primary signal is the exact ack list. `appliedCommandIDs` is bounded, though,
    /// so an ack can age out of the window before the watch ever reads it — hence the
    /// per-kind fallback in `hasLanded`.
    ///
    /// Eviction stops at the first survivor for a workout: the queue is ordered, and a
    /// command whose predecessor hasn't landed can't have landed either (the phone
    /// applies them in the order they arrive). Without that, a queued `finish` would
    /// look "landed" simply because the `start` in front of it hasn't run yet and the
    /// workout isn't active on the phone.
    static func reconcile(pending: [WatchPendingCommand], with context: WatchContext) -> [WatchPendingCommand] {
        let applied = Set(context.appliedCommandIDs)
        var stuck: Set<UUID> = []
        var remaining: [WatchPendingCommand] = []
        for entry in pending {
            if !stuck.contains(entry.workoutID),
               applied.contains(entry.command.commandID) || hasLanded(entry, in: context) {
                continue
            }
            stuck.insert(entry.workoutID)
            remaining.append(entry)
        }
        return remaining
    }

    /// Whether the phone's state already reflects this command, judged without the ack.
    private static func hasLanded(_ entry: WatchPendingCommand, in context: WatchContext) -> Bool {
        switch entry.command {
        case .start:
            // Version arithmetic is the wrong tool here: editing a plan on the phone
            // bumps its version too, which would read as "already started" and throw
            // away a start that never ran. What actually settles it is the workout no
            // longer being offered as a plan.
            return !context.plans.contains { $0.id == entry.workoutID }
        case .finish:
            // Unlike `.start`, there's no structural signal here: a workout that's
            // merely still active (not yet finished) also isn't in `plans` — started
            // workouts never are — so "no snapshot for this ID right now" is true for
            // all sorts of unrelated reasons (a context pushed before the command even
            // arrived, a different workout's push) and isn't proof this one landed. The
            // explicit ack (`context.appliedCommandIDs`, checked by the caller before
            // this) is the only safe signal for `.finish`.
            return false
        case .logSet:
            // A logged set is exactly what the version counts, so here the version is
            // the signal — the phone reaching the expected version means it applied it.
            guard let remote = remoteVersion(of: entry.workoutID, in: context) else { return false }
            return remote >= entry.expectedVersion
        }
    }

    /// The version the phone currently reports for a workout, or nil when it doesn't
    /// know about it at all (already finished, or never delivered).
    static func remoteVersion(of workoutID: UUID, in context: WatchContext?) -> Int? {
        guard let context else { return nil }
        if let snapshot = context.snapshot, snapshot.workoutID == workoutID { return snapshot.version }
        return context.plans.first(where: { $0.id == workoutID })?.version
    }

    /// Version the watch believes the workout is at: what the phone reported plus every
    /// queued command that hasn't landed yet.
    static func localVersion(of workoutID: UUID, in context: WatchContext?, pending: [WatchPendingCommand]) -> Int {
        let base = remoteVersion(of: workoutID, in: context) ?? 0
        return base + pending.filter { $0.workoutID == workoutID }.count
    }

    /// The workout the watch started itself and the phone hasn't confirmed yet.
    static func locallyStartedWorkoutID(in pending: [WatchPendingCommand]) -> UUID? {
        pending.last(where: { if case .start = $0.command { return true } else { return false } })?.workoutID
    }

    /// The active workout as the watch should display it: the phone's snapshot with the
    /// still-unsent commands folded in, or a plan the watch started while offline,
    /// promoted to an active snapshot. Nil once a queued `finish` covers it.
    static func activeSnapshot(in context: WatchContext?, pending: [WatchPendingCommand]) -> WatchWorkoutSnapshot? {
        var base: WatchWorkoutSnapshot?
        if let startedID = locallyStartedWorkoutID(in: pending) {
            if let snapshot = context?.snapshot, snapshot.workoutID == startedID {
                base = snapshot
            } else if let plan = context?.plans.first(where: { $0.id == startedID }) {
                base = promote(plan)
            }
        }
        if base == nil { base = context?.snapshot }
        guard let base else { return nil }

        let forWorkout = pending.filter { $0.workoutID == base.workoutID }
        if forWorkout.contains(where: { if case .finish = $0.command { return true } else { return false } }) {
            return nil
        }

        guard !forWorkout.isEmpty else { return base }

        let logged = forWorkout.compactMap { entry -> WatchLogSetCommand? in
            if case .logSet(let command) = entry.command { return command }
            return nil
        }
        let exercises = base.exercises.map { info -> WatchWorkoutSnapshot.ExerciseInfo in
            let mine = logged.filter { $0.exerciseID == info.id }
            guard let last = mine.last else { return info }
            let count = info.setsLoggedCount + mine.count
            let planned = count < info.plannedSets.count ? info.plannedSets[count] : nil
            return WatchWorkoutSnapshot.ExerciseInfo(
                id: info.id,
                name: info.name,
                setsLoggedCount: count,
                weight: planned?.weight ?? last.weight,
                reps: planned?.reps ?? last.reps,
                plannedSets: info.plannedSets
            )
        }
        return WatchWorkoutSnapshot(
            workoutID: base.workoutID,
            name: base.name,
            date: base.date,
            version: base.version + forWorkout.count,
            exercises: exercises,
            restEndDate: base.restEndDate,
            restExerciseName: base.restExerciseName
        )
    }

    /// Plans to list, minus the one the watch already started locally.
    static func plans(in context: WatchContext?, pending: [WatchPendingCommand]) -> [WatchWorkoutSummary] {
        guard let context else { return [] }
        let startedID = locallyStartedWorkoutID(in: pending)
        return context.plans.filter { $0.id != startedID }
    }

    /// A queue that's draining normally is not worth a line of screen space on a watch:
    /// commands go out within a second of being logged. The status only earns its place
    /// once something is actually stuck — either the oldest entry has been waiting past
    /// `queueWarningDelay`, or more than `queueWarningCount` have piled up (which, at
    /// one entry per set, means the phone has been out of range for a good while).
    static let queueWarningCount = 5
    static let queueWarningDelay: TimeInterval = 300

    static func shouldWarnAboutQueue(_ pending: [WatchPendingCommand], now: Date) -> Bool {
        if pending.count > queueWarningCount { return true }
        guard let oldest = pending.map(\.queuedAt).min() else { return false }
        return now.timeIntervalSince(oldest) >= queueWarningDelay
    }

    /// The moment the queue would start warning on age alone — what a `TimelineView` on
    /// the watch schedules itself against, so the line appears without a user action.
    static func queueWarningDate(_ pending: [WatchPendingCommand]) -> Date? {
        pending.map(\.queuedAt).min()?.addingTimeInterval(queueWarningDelay)
    }

    /// A plan turned into an active snapshot — the watch's optimistic view while the
    /// `start` command is still queued. Keeps the plan's own `date` rather than "now":
    /// the phone stamps the real start time in `Workout.start()` and the next snapshot
    /// carries it, and a moving date here would make this function non-deterministic
    /// for no visible gain.
    static func promote(_ plan: WatchWorkoutSummary) -> WatchWorkoutSnapshot {
        WatchWorkoutSnapshot(
            workoutID: plan.id,
            name: plan.name,
            date: plan.date,
            version: plan.version,
            exercises: plan.exercises,
            restEndDate: nil,
            restExerciseName: nil
        )
    }
}
