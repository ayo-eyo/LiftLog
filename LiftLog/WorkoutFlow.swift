import Foundation
import SwiftData

/// Whether logging a set should move the exercise screen on — FR-2's decision, pulled
/// out of the view as a pure function so it's testable (`body` isn't — see the
/// `create-tests` skill §8).
enum WorkoutFlow {
    enum Advance: Equatable {
        case stay
        case next(Exercise)
        case planFulfilled

        // Hand-written: comparing `Exercise` (a `@Model` reference type) by identity
        // rather than relying on whatever equality SwiftData synthesizes for it.
        static func == (lhs: Advance, rhs: Advance) -> Bool {
            switch (lhs, rhs) {
            case (.stay, .stay), (.planFulfilled, .planFulfilled):
                return true
            case (.next(let a), .next(let b)):
                return a.persistentModelID == b.persistentModelID
            default:
                return false
            }
        }
    }

    /// `wasFulfilled` must be read **before** logging the set. The transition that
    /// should move the screen on is remaining reaching 0, not remaining already being
    /// 0 — without this, every set logged beyond the plan would advance the screen
    /// again.
    static func advance(after exercise: Exercise, wasFulfilled: Bool, in workout: Workout) -> Advance {
        guard !wasFulfilled, workout.isSetPlanFulfilled(for: exercise) else { return .stay }
        if let next = workout.nextUnfulfilledExercise(after: exercise) {
            return .next(next)
        }
        return .planFulfilled
    }
}
