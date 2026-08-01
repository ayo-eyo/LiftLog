import Foundation
import SwiftData

@Model
final class WorkoutTemplate {
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \TemplateItem.template) var items: [TemplateItem] = []

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }

    var sortedItems: [TemplateItem] {
        items.sorted { $0.order < $1.order }
    }

    func addExercise(_ exercise: Exercise, weight: Double, reps: Int, context: ModelContext) {
        let item = TemplateItem(exercise: exercise, defaultWeight: weight, defaultReps: reps, order: items.count)
        context.insert(item)
        items.append(item)
    }
}
