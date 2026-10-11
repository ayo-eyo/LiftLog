import Foundation
import Observation

/// «Следующая тренировка» for a workout finished from the watch while its own screen isn't
/// showing — the phone on the list, a workout started from the watch and never opened on
/// the phone, or the `.finish` delivered at launch. `WorkoutDetailView` brings the sheet
/// up itself when it's on screen (its `onChange(of: completedAt)`); everything else goes
/// through here and `RootTabView` presents it.
@MainActor
@Observable
final class NextPlanPrompt {
    /// The finished workout waiting for «Следующая тренировка»; `RootTabView` clears it
    /// when the sheet closes.
    var workout: Workout?
    /// The workout whose `WorkoutDetailView` is on screen right now, so a finish from the
    /// watch is left to that screen instead of showing the sheet twice.
    var visibleWorkoutID: UUID?

    /// Called right after the watch finished `workout`.
    func workoutFinishedFromWatch(_ workout: Workout) {
        guard WorkoutProgression.hasPlan(workout), visibleWorkoutID != workout.syncID else { return }
        self.workout = workout
    }
}
