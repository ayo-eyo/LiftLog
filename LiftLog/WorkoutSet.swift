import Foundation
import SwiftData

@Model
final class WorkoutSet {
    var weight: Double
    var reps: Int
    var createdAt: Date
    /// Tiebreaker for sorts by `createdAt`, which alone isn't strictly increasing —
    /// two sets logged in quick succession (e.g. a batch of watch commands delivered
    /// via `transferUserInfo`) can share a timestamp. Callers assign this as
    /// `(existing sets' max order ?? -1) + 1` at insertion time.
    var order: Int = 0
    var exercise: Exercise?
    var workout: Workout?

    init(weight: Double, reps: Int, exercise: Exercise? = nil, workout: Workout? = nil, createdAt: Date = .now, order: Int = 0) {
        self.weight = weight
        self.reps = reps
        self.exercise = exercise
        self.workout = workout
        self.createdAt = createdAt
        self.order = order
    }
}
