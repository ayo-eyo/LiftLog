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
}
