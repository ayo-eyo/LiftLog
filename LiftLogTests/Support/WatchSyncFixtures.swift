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

    /// The exact `[String: Any]` a watch `sendMessage` / `transferUserInfo` carries.
    static func logSetMessage(_ command: WatchLogSetCommand) throws -> [String: Any] {
        ["logSet": try encoder.encode(command)]
    }

    static func skipRestMessage() -> [String: Any] {
        ["skipRest": true]
    }

    /// A payload the phone must reject without crashing or mutating the store.
    static func malformedLogSetMessage() -> [String: Any] {
        ["logSet": Data("not json".utf8)]
    }

    // MARK: Phone → watch

    static func snapshot(
        workoutID: UUID = UUID(),
        exercises: [WatchWorkoutSnapshot.ExerciseInfo] = [],
        restEndDate: Date? = nil,
        restExerciseName: String? = nil
    ) -> WatchWorkoutSnapshot {
        WatchWorkoutSnapshot(
            workoutID: workoutID,
            exercises: exercises,
            restEndDate: restEndDate,
            restExerciseName: restExerciseName
        )
    }

    static func exerciseInfo(
        id: UUID = UUID(),
        name: String = "Жим лёжа",
        setsLoggedCount: Int = 0,
        weight: Double? = 60,
        reps: Int? = 8
    ) -> WatchWorkoutSnapshot.ExerciseInfo {
        WatchWorkoutSnapshot.ExerciseInfo(
            id: id,
            name: name,
            setsLoggedCount: setsLoggedCount,
            weight: weight,
            reps: reps
        )
    }

    /// Encodes the way `WatchSessionManager.pushSnapshot` does, then decodes the
    /// way `PhoneSessionManager.applyContext` does — the full round trip.
    static func roundTrip(_ snapshot: WatchWorkoutSnapshot?) throws -> WatchWorkoutSnapshot? {
        let data = try encoder.encode(WatchContext(snapshot: snapshot))
        return try decoder.decode(WatchContext.self, from: data).snapshot
    }

    /// The application-context dictionary the phone hands to `updateApplicationContext`.
    static func applicationContext(_ snapshot: WatchWorkoutSnapshot?) throws -> [String: Any] {
        ["data": try encoder.encode(WatchContext(snapshot: snapshot))]
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
