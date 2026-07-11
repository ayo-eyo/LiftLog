import Foundation
import SwiftData

@Model
final class Exercise {
    var name: String
    var createdAt: Date
    var catalogID: String?
    @Relationship(inverse: \WorkoutSet.exercise) var sets: [WorkoutSet] = []

    init(name: String, catalogID: String? = nil, createdAt: Date = .now) {
        self.name = name
        self.catalogID = catalogID
        self.createdAt = createdAt
    }
    
    func addSet(weight: Double, reps: Int, context: ModelContext) {
        let new = WorkoutSet(weight: weight, reps: reps)
        context.insert(new)
        sets.append(new)
    }
}
