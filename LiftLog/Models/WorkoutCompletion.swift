import Foundation
import SwiftData
import os

extension Workout {
    private static let completionLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LiftLog", category: "WorkoutCompletion")

    /// The one path every "finish the workout" action funnels through — the phone's
    /// own «Завершить» button, the plan-fulfilled banner on the exercise screen, and a
    /// finish command from the watch. Before this existed the phone and watch sides
    /// each reimplemented the same sequence by hand and had already drifted (see
    /// plans/features/workout-automation/technical-notes.md §2).
    ///
    /// Saves the context itself rather than relying on the caller's autosave — the
    /// watch-driven call site runs while iOS may kill the app immediately after
    /// replying, which is exactly the FR-5 bug (technical-notes.md §5.1).
    // `watchSession` defaults to `nil` and is resolved to `.shared` inside the body
    // rather than as a default-parameter expression — `WatchSessionManager.shared` is
    // main-actor-isolated (the project defaults every type to `@MainActor`), and a
    // default-parameter expression evaluates outside the function's own isolation
    // (same reasoning as `HealthKitManager.save`'s `savingStore` parameter).
    @MainActor
    static func complete(_ workout: Workout, restTimer: RestTimer?, context: ModelContext, watchSession: WatchSessionManager? = nil) {
        let watchSession = watchSession ?? .shared
        restTimer?.skip()
        workout.finish()
        do {
            try context.save()
        } catch {
            completionLogger.error("не удалось сохранить завершение тренировки: \(error.localizedDescription)")
        }
        Task { await HealthKitManager.save(workout) }
        watchSession.pushSnapshot(for: nil)
    }
}
