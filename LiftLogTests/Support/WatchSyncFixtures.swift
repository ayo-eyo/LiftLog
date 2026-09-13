import Foundation
@testable import LiftLog

/// Helpers for the WatchConnectivity wire format.
///
/// The DTOs in `WorkoutSyncModels.swift` exist verbatim in both targets, so these
/// builders double as the reference encoder for "what the watch would actually
/// put on the wire" — a test can hand the resulting dictionary straight to
/// `WatchSessionManager`'s message handling.
@MainActor
enum WatchSyncFixtures {
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    // MARK: Watch → phone

    static func logSetCommand(
        workoutID: UUID,
        exerciseID: UUID,
        commandID: UUID = UUID(),
        exerciseName: String = "Жим лёжа",
        weight: Double = 60,
        reps: Int = 8
    ) -> WatchLogSetCommand {
        WatchLogSetCommand(
            commandID: commandID,
            workoutID: workoutID,
            exerciseID: exerciseID,
            exerciseName: exerciseName,
            weight: weight,
            reps: reps
        )
    }

    static func startCommand(workoutID: UUID, commandID: UUID = UUID()) -> WatchStartWorkoutCommand {
        WatchStartWorkoutCommand(commandID: commandID, workoutID: workoutID)
    }

    static func finishCommand(workoutID: UUID, commandID: UUID = UUID()) -> WatchFinishWorkoutCommand {
        WatchFinishWorkoutCommand(commandID: commandID, workoutID: workoutID)
    }

    static func healthRecordedCommand(workoutID: UUID, commandID: UUID = UUID()) -> WatchHealthRecordedCommand {
        WatchHealthRecordedCommand(commandID: commandID, workoutID: workoutID)
    }

    /// The exact `[String: Any]` a watch `sendMessage` / `transferUserInfo` carries.
    static func commandMessage(_ command: WatchCommand) throws -> [String: Any] {
        [WatchMessageKey.command: try encoder.encode(command)]
    }

    /// The pre-`WatchCommand` message an older watch build still sends.
    static func legacyLogSetMessage(_ command: WatchLogSetCommand) throws -> [String: Any] {
        [WatchMessageKey.legacyLogSet: try encoder.encode(command)]
    }

    static func skipRestMessage() -> [String: Any] {
        [WatchMessageKey.skipRest: true]
    }

    /// The "send me what you have now" message the watch puts on the wire when it can't
    /// trust the last context it was pushed (activation, reachability, foreground).
    static func requestContextMessage() -> [String: Any] {
        [WatchMessageKey.requestContext: true]
    }

    /// A payload the phone must reject without crashing or mutating the store.
    static func malformedLogSetMessage() -> [String: Any] {
        [WatchMessageKey.legacyLogSet: Data("not json".utf8)]
    }

    /// One queued command as the watch stores it, with the version it expects the
    /// workout to reach once the phone applies it.
    static func pending(
        _ command: WatchCommand,
        expectedVersion: Int,
        queuedAt: Date = Fixtures.epoch
    ) -> WatchPendingCommand {
        WatchPendingCommand(command: command, expectedVersion: expectedVersion, queuedAt: queuedAt)
    }

    /// `count` queued sets for one workout, all queued at the same moment.
    static func pendingSets(_ count: Int, workoutID: UUID = UUID(), queuedAt: Date = Fixtures.epoch) -> [WatchPendingCommand] {
        (0..<count).map { index in
            pending(
                .logSet(logSetCommand(workoutID: workoutID, exerciseID: UUID())),
                expectedVersion: index + 1,
                queuedAt: queuedAt
            )
        }
    }

    // MARK: Phone → watch

    static func snapshot(
        workoutID: UUID = UUID(),
        name: String = "",
        date: Date = Fixtures.epoch,
        version: Int = 0,
        exercises: [WatchWorkoutSnapshot.ExerciseInfo] = [],
        restEndDate: Date? = nil,
        restExerciseName: String? = nil
    ) -> WatchWorkoutSnapshot {
        WatchWorkoutSnapshot(
            workoutID: workoutID,
            name: name,
            date: date,
            version: version,
            exercises: exercises,
            restEndDate: restEndDate,
            restExerciseName: restExerciseName
        )
    }

    static func summary(
        id: UUID = UUID(),
        name: String = "План",
        date: Date = Fixtures.epoch,
        version: Int = 0,
        exercises: [WatchWorkoutSnapshot.ExerciseInfo] = []
    ) -> WatchWorkoutSummary {
        WatchWorkoutSummary(id: id, name: name, date: date, version: version, exercises: exercises)
    }

    static func exerciseInfo(
        id: UUID = UUID(),
        name: String = "Жим лёжа",
        setsLoggedCount: Int = 0,
        weight: Double? = 60,
        reps: Int? = 8,
        plannedSets: [WatchWorkoutSnapshot.PlannedSet] = []
    ) -> WatchWorkoutSnapshot.ExerciseInfo {
        WatchWorkoutSnapshot.ExerciseInfo(
            id: id,
            name: name,
            setsLoggedCount: setsLoggedCount,
            weight: weight,
            reps: reps,
            plannedSets: plannedSets
        )
    }

    static func plannedSets(_ sets: [(weight: Double?, reps: Int?)]) -> [WatchWorkoutSnapshot.PlannedSet] {
        sets.map { WatchWorkoutSnapshot.PlannedSet(weight: $0.weight, reps: $0.reps) }
    }

    static func context(
        snapshot: WatchWorkoutSnapshot? = nil,
        plans: [WatchWorkoutSummary] = [],
        appliedCommandIDs: [UUID] = []
    ) -> WatchContext {
        WatchContext(snapshot: snapshot, plans: plans, appliedCommandIDs: appliedCommandIDs)
    }

    /// Encodes the way `WatchSessionManager.push` does, then decodes the way
    /// `PhoneSessionManager.apply(contextData:)` does — the full round trip.
    static func roundTrip(_ snapshot: WatchWorkoutSnapshot?) throws -> WatchWorkoutSnapshot? {
        try roundTrip(WatchContext(snapshot: snapshot)).snapshot
    }

    static func roundTrip(_ context: WatchContext) throws -> WatchContext {
        let data = try encoder.encode(context)
        return try decoder.decode(WatchContext.self, from: data)
    }

    /// The application-context dictionary the phone hands to `updateApplicationContext`.
    static func applicationContext(_ snapshot: WatchWorkoutSnapshot?) throws -> [String: Any] {
        try applicationContext(WatchContext(snapshot: snapshot))
    }

    static func applicationContext(_ context: WatchContext) throws -> [String: Any] {
        ["data": try encoder.encode(context)]
    }
}

/// Paths to the two hand-synced copies of the wire format, for the parity check
/// that guards against one target's DTOs drifting from the other's.
/// `SourcePaths.repoRoot` is derived from `#filePath`, so it works in the
/// simulator where the repo is not otherwise reachable from the test bundle.
enum SourcePaths {
    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Support
        .deletingLastPathComponent() // LiftLogTests
        .deletingLastPathComponent() // repo root

    static let phoneSyncModels = repoRoot.appending(path: "LiftLog/WorkoutSyncModels.swift")
    static let watchSyncModels = repoRoot.appending(path: "LiftLogWatchApp Watch App/WorkoutSyncModels.swift")
}
