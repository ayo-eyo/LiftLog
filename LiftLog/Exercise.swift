import Foundation
import SwiftData

@Model
final class Exercise {
    var syncID: UUID = UUID()
    var name: String
    var createdAt: Date
    var catalogID: String?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.exercise) var sets: [WorkoutSet] = []

    init(name: String, catalogID: String? = nil, createdAt: Date = .now) {
        self.syncID = UUID()
        self.name = name
        self.catalogID = catalogID
        self.createdAt = createdAt
    }

    func addSet(weight: Double, reps: Int, context: ModelContext) {
        let order = (sets.map(\.order).max() ?? -1) + 1
        let new = WorkoutSet(weight: weight, reps: reps, order: order)
        context.insert(new)
        sets.append(new)
    }

    var catalogExercise: CatalogExercise? {
        catalogID.flatMap { ExerciseCatalog.byID[$0] }
    }

    var primaryMuscles: [String] { catalogExercise?.primaryMuscles ?? [] }
    var secondaryMuscles: [String] { catalogExercise?.secondaryMuscles ?? [] }
}
