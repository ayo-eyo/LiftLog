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

    /// Deletes `set` from the store and from both in-memory relationship arrays
    /// it can belong to (`exercise.sets`, `workout.sets`) — `context.delete` alone
    /// doesn't prune it out of an already-loaded relationship array until the next
    /// save/fetch, same reasoning as `Workout.deleteExercise`. `workout` is nil for
    /// a set logged outside any workout (`ExerciseDetailView`'s standalone flow).
    static func delete(_ set: WorkoutSet, context: ModelContext) {
        context.delete(set)
        set.exercise?.sets.removeAll { $0.persistentModelID == set.persistentModelID }
        set.workout?.sets.removeAll { $0.persistentModelID == set.persistentModelID }
    }
}
