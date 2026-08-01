import Foundation
import SwiftData

@Model
final class Workout {
    var date: Date
    var completedAt: Date?
    var exercises: [Exercise] = []
    @Relationship(inverse: \WorkoutSet.workout) var sets: [WorkoutSet] = []

    init(date: Date = .now) {
        self.date = date
    }

    var isActive: Bool { completedAt == nil }

    func addExercise(_ exercise: Exercise) {
        guard !exercises.contains(where: { $0.persistentModelID == exercise.persistentModelID }) else { return }
        exercises.append(exercise)
    }

    func logSet(weight: Double, reps: Int, for exercise: Exercise, context: ModelContext) {
        let new = WorkoutSet(weight: weight, reps: reps)
        context.insert(new)
        sets.append(new)
        exercise.sets.append(new)
    }

    func setsFor(_ exercise: Exercise) -> [WorkoutSet] {
        sets
            .filter { $0.exercise?.persistentModelID == exercise.persistentModelID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func finish() {
        completedAt = .now
    }
}
