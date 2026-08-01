import Foundation
import SwiftData

@Model
final class TemplateItem {
    var defaultWeight: Double
    var defaultReps: Int
    var order: Int
    var exercise: Exercise?
    var template: WorkoutTemplate?

    init(exercise: Exercise?, defaultWeight: Double, defaultReps: Int, order: Int) {
        self.exercise = exercise
        self.defaultWeight = defaultWeight
        self.defaultReps = defaultReps
        self.order = order
    }
}
