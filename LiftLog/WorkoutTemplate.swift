import Foundation
import SwiftData

@Model
final class WorkoutTemplate {
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \TemplateItem.template) var items: [TemplateItem] = []
    /// Declares the inverse of `Workout.template` so SwiftData nullifies it when a
    /// template is deleted — without an inverse, a deleted template's `Workout`
    /// references are left dangling instead of clearing.
    @Relationship(deleteRule: .nullify, inverse: \Workout.template) var workouts: [Workout] = []

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }

    var sortedItems: [TemplateItem] {
        items.sorted { $0.order < $1.order }
    }

    func addExercise(_ exercise: Exercise, weight: Double, reps: Int, context: ModelContext) {
        // Deletion doesn't renumber remaining items, so `items.count` can collide with an
        // existing `order` (e.g. 3 items 0/1/2 → delete #0 → 2 remain → count == 2 collides
        // with the surviving item at order 2). max+1 never collides, gaps are harmless since
        // `sortedItems` only cares about relative order.
        let order = (items.map(\.order).max() ?? -1) + 1
        let item = TemplateItem(exercise: exercise, defaultWeight: weight, defaultReps: reps, order: order)
        context.insert(item)
        items.append(item)
    }
}
