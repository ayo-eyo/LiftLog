import Foundation
import SwiftData

/// One-time repair for records written before `Exercise`/`Workout` explicitly
/// assigned `syncID` in `init()`. SwiftData's default-value expressions for
/// `@Model` properties are captured once at the schema level rather than
/// re-evaluated per insert, so every record created before that fix shares the
/// same `syncID` — which the watch sync (`WatchWorkoutSnapshot.ExerciseInfo`)
/// uses as its `Identifiable` id, collapsing the exercise list to one row.
/// Safe to call on every launch: it's a no-op once ids are unique.
enum DataIntegrity {
    static func deduplicateSyncIDs(context: ModelContext) {
        deduplicate(FetchDescriptor<Exercise>(), keyPath: \Exercise.syncID, context: context)
        deduplicate(FetchDescriptor<Workout>(), keyPath: \Workout.syncID, context: context)
    }

    private static func deduplicate<T: PersistentModel>(
        _ descriptor: FetchDescriptor<T>,
        keyPath: ReferenceWritableKeyPath<T, UUID>,
        context: ModelContext
    ) {
        guard let items = try? context.fetch(descriptor) else { return }
        var seen = Set<UUID>()
        var changed = false
        for item in items {
            if seen.contains(item[keyPath: keyPath]) {
                item[keyPath: keyPath] = UUID()
                changed = true
            } else {
                seen.insert(item[keyPath: keyPath])
            }
        }
        if changed {
            try? context.save()
        }
    }

    /// One-time backfill for the `WorkoutTemplate`/`TemplateItem` removal: a
    /// workout's composition used to live in `Workout.exercises` (an unmanaged,
    /// unordered array), which the migration drops along with the removed
    /// entities. `WorkoutItem` didn't exist before, so every pre-existing workout
    /// comes back from the migration with an empty `items` and no way to tell
    /// which exercises it had — except its `WorkoutSet`s, which are still there.
    ///
    /// For each such workout, this reconstructs one planned position per logged
    /// set, using the set's own weight/reps as the plan. Exercises ordered by
    /// their earliest set's `createdAt` (the closest available signal to "the
    /// order exercises were added in"), sets within an exercise by
    /// `(createdAt, order)` — same tiebreak `Workout.setsFor` uses. An exercise
    /// that was added to a workout but never logged a set can't be recovered this
    /// way and is an accepted loss (see FR-7 in
    /// plans/features/delete-fixture/requirements.md).
    ///
    /// Idempotent and safe on every launch: it only touches workouts with no
    /// items yet, so a workout that already went through this (or was created
    /// after the migration) is left alone.
    static func restoreWorkoutComposition(context: ModelContext) {
        guard let workouts = try? context.fetch(FetchDescriptor<Workout>()) else { return }
        var changed = false
        for workout in workouts where workout.items.isEmpty && !workout.sets.isEmpty {
            let grouped = Dictionary(grouping: workout.sets.filter { $0.exercise != nil }) { $0.exercise!.persistentModelID }
            let exerciseOrder = grouped.keys.sorted { lhs, rhs in
                let lhsMin = grouped[lhs]?.map(\.createdAt).min() ?? .distantFuture
                let rhsMin = grouped[rhs]?.map(\.createdAt).min() ?? .distantFuture
                return lhsMin < rhsMin
            }

            var order = 0
            for exerciseID in exerciseOrder {
                guard let sets = grouped[exerciseID] else { continue }
                let sortedSets = sets.sorted { ($0.createdAt, $0.order) < ($1.createdAt, $1.order) }
                for set in sortedSets {
                    let item = WorkoutItem(exercise: set.exercise, plannedWeight: set.weight, plannedReps: set.reps, order: order)
                    context.insert(item)
                    workout.items.append(item)
                    order += 1
                }
            }
            changed = true
        }
        if changed {
            try? context.save()
        }
    }
}
