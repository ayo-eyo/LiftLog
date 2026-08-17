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
    }

    /// Removes a single planned position — as opposed to `deleteExercise`, which
    /// removes every position for an exercise plus its logged sets. Same in-memory
    /// cleanup reasoning as `deleteExercise`: `context.delete` alone doesn't prune
    /// `item` out of `items` until the next save/fetch.
    func deleteItem(_ item: WorkoutItem, context: ModelContext) {
        context.delete(item)
        items.removeAll { $0.persistentModelID == item.persistentModelID }
    }

    func logSet(weight: Double, reps: Int, for exercise: Exercise, context: ModelContext) {
        let order = (sets.map(\.order).max() ?? -1) + 1
        let new = WorkoutSet(weight: weight, reps: reps, order: order)
        context.insert(new)
        sets.append(new)
        exercise.sets.append(new)
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
    }

    func finish(now: Date = .now) {
        completedAt = now
    }

    /// The next unlogged planned position for `exercise`: the N-th logged set for
    /// an exercise is matched against the N-th planned position for it, same
    /// positional scheme as the old `Workout.templateItem(for:)`.
    private func plannedItem(for exercise: Exercise) -> WorkoutItem? {
        let planned = sortedItems.filter { $0.exercise?.persistentModelID == exercise.persistentModelID }
        let logged = setsFor(exercise).count
        guard logged < planned.count else { return nil }
        return planned[logged]
    }

    func defaultWeight(for exercise: Exercise) -> Double? {
        plannedItem(for: exercise)?.plannedWeight
    }

    func defaultReps(for exercise: Exercise) -> Int? {
        plannedItem(for: exercise)?.plannedReps
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
