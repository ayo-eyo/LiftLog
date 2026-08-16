import Foundation

/// Wire format exchanged over WatchConnectivity between the iPhone and the Watch app.
/// Kept as a plain Codable DTO (not the SwiftData models themselves) since the watch
/// has no SwiftData store of its own — it only mirrors what the phone sends.
struct WatchContext: Codable {
    let snapshot: WatchWorkoutSnapshot?
}

struct WatchWorkoutSnapshot: Codable {
    struct ExerciseInfo: Codable, Identifiable {
        let id: UUID
        let name: String
        let setsLoggedCount: Int
        let weight: Double?
        let reps: Int?
    }

    let workoutID: UUID
    let exercises: [ExerciseInfo]
    let restEndDate: Date?
    let restExerciseName: String?
}

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
