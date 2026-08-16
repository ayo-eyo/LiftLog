import Foundation
import SwiftData

@Model
final class Workout {
    var syncID: UUID = UUID()
    var date: Date
    var completedAt: Date?
    var exercises: [Exercise] = []
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.workout) var sets: [WorkoutSet] = []
    
    init(date: Date = .now) {
        self.syncID = UUID()
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
    
    var template: WorkoutTemplate?

    func applyTemplate(_ template: WorkoutTemplate) {
        self.template = template
        for item in template.sortedItems {
            if let exercise = item.exercise {
                addExercise(exercise)
            }
        }
    }

    private func templateItem(for exercise: Exercise) -> TemplateItem? {
        guard let template else { return nil }
        let planned = template.sortedItems.filter { $0.exercise?.persistentModelID == exercise.persistentModelID }
        let logged = setsFor(exercise).count
        guard logged < planned.count else { return nil }
        return planned[logged]
    }

    func defaultWeight(for exercise: Exercise) -> Double? {
        templateItem(for: exercise)?.defaultWeight
    }

    func defaultReps(for exercise: Exercise) -> Int? {
        templateItem(for: exercise)?.defaultReps
    }
}
