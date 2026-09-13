import Foundation
import SwiftData

/// One planned position in a workout: one exercise plus its planned weight/reps.
/// An exercise added mid-workout without numbers has both planned values `nil`.
/// One exercise can occupy several consecutive positions — that's a plan for
/// several sets, the same role `TemplateItem` used to play on `WorkoutTemplate`.
@Model
final class WorkoutItem {
    var order: Int
    var plannedWeight: Double?
    var plannedReps: Int?
    var exercise: Exercise?
    var workout: Workout?

    init(exercise: Exercise?, plannedWeight: Double? = nil, plannedReps: Int? = nil, order: Int) {
        self.exercise = exercise
        self.plannedWeight = plannedWeight
        self.plannedReps = plannedReps
        self.order = order
    }
}
