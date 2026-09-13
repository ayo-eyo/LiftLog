import Foundation
import SwiftData

/// The three states in the table on `isActive` — computed from `startedAt`/
/// `completedAt` rather than stored, so it can never drift from them.
nonisolated enum WorkoutStatus {
    case plan
    case active
    case completed
}

@Model
final class Workout {
    var syncID: UUID = UUID()
    var date: Date
    var name: String = ""
    /// nil until `start()` is called. Together with `completedAt` this drives
    /// `isActive` — see the three-state table in plans/features/delete-fixture.
    var startedAt: Date?
    var completedAt: Date?
    /// Manual order in the workout list. Left at 0 until the user drags a row;
    /// while everything is 0 the list falls back to date order (see `WorkoutListView`).
    var sortIndex: Int = 0
    /// Monotonic counter bumped by one on every change to the workout's contents —
    /// see `bumpVersion()`. Rides in the watch snapshot so the watch can tell whether
    /// the phone has caught up with the sets it logged offline.
    var version: Int = 0
    /// Set when the watch reports it is recording this workout into Health with a live
    /// workout session (heart rate, energy). The phone's own save carries only start and
    /// end, so it steps aside — see `HealthKitManager.save` and
    /// `WatchSessionManager.healthRecorded`.
    var healthRecordedOnWatch: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \WorkoutItem.workout) var items: [WorkoutItem] = []
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.workout) var sets: [WorkoutSet] = []

    init(date: Date = .now, name: String = "", sortIndex: Int = 0) {
        self.syncID = UUID()
        self.date = date
        self.name = name
        self.sortIndex = sortIndex
    }

    var status: WorkoutStatus {
        if completedAt != nil { return .completed }
        if startedAt != nil { return .active }
        return .plan
    }

    var isActive: Bool { status == .active }

    /// Bumps `version` by one. The rule the watch relies on is "one logged set = +1";
    /// the other call sites (plan edits, start/finish) only have to keep the counter
    /// monotonic, since the watch clears its queue by `commandID` and reads the version
    /// only to decide whether the phone has caught up with it.
    func bumpVersion() {
        version += 1
    }

    var sortedItems: [WorkoutItem] {
        items.sorted { $0.order < $1.order }
    }

    /// The distinct exercises in `sortedItems`, in order of first appearance.
    var orderedExercises: [Exercise] {
        var seen = Set<PersistentIdentifier>()
        var result: [Exercise] = []
        for item in sortedItems {
            guard let exercise = item.exercise else { continue }
            if seen.insert(exercise.persistentModelID).inserted {
                result.append(exercise)
            }
        }
        return result
    }

    /// `sortedItems` grouped by exercise, one group per exercise in order of
    /// first appearance — the shape both the reorder UI and `moveExercise` need.
    var groupedItems: [(exercise: Exercise, items: [WorkoutItem])] {
        var order: [PersistentIdentifier] = []
        var groups: [PersistentIdentifier: (Exercise, [WorkoutItem])] = [:]
        for item in sortedItems {
            guard let exercise = item.exercise else { continue }
            let id = exercise.persistentModelID
            if groups[id] == nil {
                groups[id] = (exercise, [])
                order.append(id)
            }
            groups[id]?.1.append(item)
        }
        return order.compactMap { id in groups[id].map { (exercise: $0.0, items: $0.1) } }
    }

    /// Adds one planned position for `exercise`. Repeated calls for the same
    /// exercise are intentional — each call is one more planned set, not a dedup
    /// check (the UI keeps exercises already in the workout out of the picker;
    /// adding another position to an already-added exercise goes through its
    /// own screen instead).
    func addExercise(_ exercise: Exercise, weight: Double? = nil, reps: Int? = nil, context: ModelContext) {
        // Deletion doesn't renumber remaining items, so `items.count` can collide with an
        // existing `order` (e.g. 3 items 0/1/2 → delete #0 → 2 remain → count == 2 collides
        // with the surviving item at order 2). max+1 never collides, gaps are harmless since
        // `sortedItems` only cares about relative order.
        let order = (items.map(\.order).max() ?? -1) + 1
        let item = WorkoutItem(exercise: exercise, plannedWeight: weight, plannedReps: reps, order: order)
        context.insert(item)
        items.append(item)
        bumpVersion()
    }

    /// Removes `exercise` from the workout entirely: its planned positions and
    /// any sets already logged for it in this workout. Removes from `items`/`sets`
    /// in memory too, not just `context.delete` — SwiftData doesn't retroactively
    /// prune a deleted object out of another object's already-loaded relationship
    /// array until the next save/fetch, so a caller reading `orderedExercises` or
    /// `setsFor` right after this call would otherwise still see the deleted rows.
    func deleteExercise(_ exercise: Exercise, context: ModelContext) {
        let itemIDs = Set(items.filter { $0.exercise?.persistentModelID == exercise.persistentModelID }.map(\.persistentModelID))
        for item in items where itemIDs.contains(item.persistentModelID) {
            context.delete(item)
        }
        items.removeAll { itemIDs.contains($0.persistentModelID) }

        let setIDs = Set(setsFor(exercise).map(\.persistentModelID))
        for set in sets where setIDs.contains(set.persistentModelID) {
            context.delete(set)
        }
        sets.removeAll { setIDs.contains($0.persistentModelID) }
        bumpVersion()
    }

    /// Reorders whole exercise groups (all of an exercise's planned positions move
    /// together), then renumbers every item's `order` sequentially across the
    /// resulting groups. Implements the same "remove then reinsert" semantics as
    /// `RangeReplaceableCollection.move(fromOffsets:toOffset:)` (SwiftUI's `List`
    /// `onMove` callback convention) without depending on SwiftUI from the model layer.
    func moveExercise(from source: IndexSet, to destination: Int) {
        var groups = groupedItems
        let moving = source.map { groups[$0] }
        for index in source.sorted(by: >) {
            groups.remove(at: index)
        }
        let adjustedDestination = destination - source.filter { $0 < destination }.count
        groups.insert(contentsOf: moving, at: adjustedDestination)

        var order = 0
        for group in groups {
            for item in group.items {
                item.order = order
                order += 1
            }
        }
        bumpVersion()
    }

    /// Removes a single planned position — as opposed to `deleteExercise`, which
    /// removes every position for an exercise plus its logged sets. Same in-memory
    /// cleanup reasoning as `deleteExercise`: `context.delete` alone doesn't prune
    /// `item` out of `items` until the next save/fetch.
    func deleteItem(_ item: WorkoutItem, context: ModelContext) {
        context.delete(item)
        items.removeAll { $0.persistentModelID == item.persistentModelID }
        bumpVersion()
    }

    func logSet(weight: Double, reps: Int, for exercise: Exercise, context: ModelContext) {
        let order = (sets.map(\.order).max() ?? -1) + 1
        let new = WorkoutSet(weight: weight, reps: reps, order: order)
        context.insert(new)
        sets.append(new)
        exercise.sets.append(new)
        bumpVersion()
    }

    func setsFor(_ exercise: Exercise) -> [WorkoutSet] {
        sets
            .filter { $0.exercise?.persistentModelID == exercise.persistentModelID }
            .sorted { ($0.createdAt, $0.order) < ($1.createdAt, $1.order) }
    }

    /// Transitions plan → active: stamps `startedAt` and moves `date` to the
    /// actual start time, so a copy that sat as a plan doesn't carry its creation
    /// date into HealthKit/the list.
    func start(now: Date = .now) {
        startedAt = now
        date = now
        bumpVersion()
    }

    func finish(now: Date = .now) {
        completedAt = now
        bumpVersion()
    }

    /// The next unlogged planned position for `exercise`: the N-th logged set for
    /// an exercise is matched against the N-th planned position for it, same
    /// positional scheme as the old `Workout.templateItem(for:)`.
    private func plannedItem(for exercise: Exercise) -> WorkoutItem? {
        let planned = sortedItems.filter { $0.exercise?.persistentModelID == exercise.persistentModelID }
        let logged = loggedSetCount(for: exercise)
        guard logged < planned.count else { return nil }
        return planned[logged]
    }

    func defaultWeight(for exercise: Exercise) -> Double? {
        plannedItem(for: exercise)?.plannedWeight
    }

    func defaultReps(for exercise: Exercise) -> Int? {
        plannedItem(for: exercise)?.plannedReps
    }

    // MARK: Set counters (FR-1)
    //
    // No new stored fields — everything here is derived from `items`/`sets`, which
    // `plannedItem(for:)` above already counted; these just expose that counting.
    // `remainingSetCount(for:) == 0` ⟺ `plannedItem(for:) == nil` ⟺ `defaultWeight`/
    // `defaultReps` stop reading from the plan — see the invariant test.

    /// Number of planned positions for `exercise` — how many sets the plan calls for.
    func plannedSetCount(for exercise: Exercise) -> Int {
        sortedItems.filter { $0.exercise?.persistentModelID == exercise.persistentModelID }.count
    }

    /// Sets actually logged for `exercise` **in this workout** — not the exercise's
    /// whole history, which several workouts can share (see `Workout.copy`).
    func loggedSetCount(for exercise: Exercise) -> Int {
        setsFor(exercise).count
    }

    /// `max(0, planned - logged)` — sets logged beyond the plan don't push this
    /// negative.
    func remainingSetCount(for exercise: Exercise) -> Int {
        max(0, plannedSetCount(for: exercise) - loggedSetCount(for: exercise))
    }

    /// Whether `exercise`'s plan is fully worked. An exercise with no planned
    /// positions (added mid-workout) is never considered fulfilled — there's nothing
    /// to fulfill, so it can't block auto-advance or count toward `isSetPlanFulfilled`.
    func isSetPlanFulfilled(for exercise: Exercise) -> Bool {
        let planned = plannedSetCount(for: exercise)
        return planned > 0 && loggedSetCount(for: exercise) >= planned
    }

    /// Whether every planned exercise in the workout is fully worked. Exercises with
    /// no plan don't count either way.
    var isSetPlanFulfilled: Bool {
        orderedExercises.allSatisfy { exercise in
            let planned = plannedSetCount(for: exercise)
            return planned == 0 || loggedSetCount(for: exercise) >= planned
        }
    }

    // MARK: Auto-advance (FR-2)

    /// The next exercise auto-advance should move to after `exercise`'s plan closes:
    /// the nearest unfulfilled, planned exercise **after** `exercise` in workout
    /// order, wrapping to the start of the list if none is left ahead — a skipped
    /// exercise earlier in the list isn't lost. `exercise` itself is never offered,
    /// and an exercise with no plan never is either (there's nothing to "arrive" at
    /// automatically, though it stays reachable by hand). `nil` once nothing is left
    /// unfulfilled. Kept in lockstep with `WatchWorkoutSnapshot.nextUnfulfilledExercise`
    /// (see the parity test) — the watch has to make the same decision offline, from
    /// its own DTO, with no shared code between the two targets.
    func nextUnfulfilledExercise(after exercise: Exercise) -> Exercise? {
        let ordered = orderedExercises
        let candidates = ordered.filter { candidate in
            candidate.persistentModelID != exercise.persistentModelID
                && plannedSetCount(for: candidate) > 0
                && remainingSetCount(for: candidate) > 0
        }
        guard !candidates.isEmpty else { return nil }
        guard let currentIndex = ordered.firstIndex(where: { $0.persistentModelID == exercise.persistentModelID }) else {
            return candidates.first
        }
        if let forward = candidates.first(where: { candidate in
            guard let index = ordered.firstIndex(where: { $0.persistentModelID == candidate.persistentModelID }) else { return false }
            return index > currentIndex
        }) {
            return forward
        }
        return candidates.first
    }
}

extension Workout {
    /// Builds a plan from `source`: same ordered exercises, planned weight/reps.
    /// Per exercise, the source's already-logged sets become the copy's plan when
    /// there are any (so a partially/fully worked exercise copies as "what was
    /// actually done"); otherwise the source's own planned positions are copied.
    /// Sets, `startedAt`/`completedAt` are never copied; `Exercise` objects are
    /// shared, not duplicated, so exercise history stays unified; the source is
    /// never mutated.
    static func copy(of source: Workout, sortIndex: Int, now: Date = .now, context: ModelContext) -> Workout {
        let copy = Workout(date: now, name: source.name, sortIndex: sortIndex)
        context.insert(copy)

        var order = 0
        for exercise in source.orderedExercises {
            let loggedSets = source.setsFor(exercise)
            if !loggedSets.isEmpty {
                for set in loggedSets {
                    let item = WorkoutItem(exercise: exercise, plannedWeight: set.weight, plannedReps: set.reps, order: order)
                    context.insert(item)
                    copy.items.append(item)
                    order += 1
                }
            } else {
                let planned = source.sortedItems.filter { $0.exercise?.persistentModelID == exercise.persistentModelID }
                for position in planned {
                    let item = WorkoutItem(exercise: exercise, plannedWeight: position.plannedWeight, plannedReps: position.plannedReps, order: order)
                    context.insert(item)
                    copy.items.append(item)
                    order += 1
                }
            }
        }
        return copy
    }

}
