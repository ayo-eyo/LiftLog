import Foundation
import SwiftData

@Model
final class WorkoutSet {
    var weight: Double
    var reps: Int
    var createdAt: Date
    var exercise: Exercise?
    var workout: Workout?

    init(weight: Double, reps: Int, exercise: Exercise? = nil, workout: Workout? = nil, createdAt: Date = .now) {
        self.weight = weight
        self.reps = reps
        self.exercise = exercise
        self.workout = workout
        self.createdAt = createdAt
    }
}
