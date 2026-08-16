import Testing
import Foundation
import SwiftData
@testable import LiftLog

/// `DataIntegrity.deduplicateSyncIDs` repairs the historical bug where SwiftData's
/// default-value expression for `syncID` was captured once at the schema level —
/// see the doc comment on `DataIntegrity.swift`.
@Suite("DataIntegrity.deduplicateSyncIDs")
struct DataIntegrityTests {
    @Test("три Exercise с одинаковым syncID становятся различны, ровно один сохраняет исходный id")
    func repairsCollidingExerciseSyncIDs() throws {
        let store = try TestStore.open()
        let shared = UUID()
        let first = Fixtures.exercise("A", in: store.context)
        let second = Fixtures.exercise("B", in: store.context)
        let third = Fixtures.exercise("C", in: store.context)
        first.syncID = shared
        second.syncID = shared
        third.syncID = shared
        try store.context.save()

        DataIntegrity.deduplicateSyncIDs(context: store.context)

        // `deduplicate` fetches without a sort descriptor, so which one of the three
        // keeps `shared` isn't contractually ordered — what's guaranteed is that
        // exactly one keeps it and all three end up distinct.
        let syncIDs = [first.syncID, second.syncID, third.syncID]
        #expect(syncIDs.filter { $0 == shared }.count == 1)
        #expect(Set(syncIDs).count == 3)
    }

    @Test("уже уникальные id не меняются")
    func doesNotTouchAlreadyUniqueIDs() throws {
        let store = try TestStore.open()
        let first = Fixtures.exercise("A", in: store.context)
        let second = Fixtures.exercise("B", in: store.context)
        let originalFirst = first.syncID
        let originalSecond = second.syncID
        try store.context.save()

        DataIntegrity.deduplicateSyncIDs(context: store.context)

        #expect(first.syncID == originalFirst)
        #expect(second.syncID == originalSecond)
    }

    @Test("то же самое отдельно для Workout, и в смешанном случае Exercise/Workout не влияют друг на друга")
    func repairsWorkoutsIndependentlyOfExercises() throws {
        let store = try TestStore.open()
        let shared = UUID()
        let firstWorkout = Fixtures.workout(in: store.context)
        let secondWorkout = Fixtures.workout(in: store.context)
        firstWorkout.syncID = shared
        secondWorkout.syncID = shared

        let exercise = Fixtures.exercise(in: store.context)
        let exerciseID = exercise.syncID
        try store.context.save()

        DataIntegrity.deduplicateSyncIDs(context: store.context)

        #expect(firstWorkout.syncID != secondWorkout.syncID)
        #expect(firstWorkout.syncID == shared || secondWorkout.syncID == shared)
        #expect(exercise.syncID == exerciseID)
    }

    @Test("пустой стор не приводит к падению")
    func emptyStoreDoesNotCrash() throws {
        let store = try TestStore.open()
        DataIntegrity.deduplicateSyncIDs(context: store.context)
        #expect(try store.count(Exercise.self) == 0)
    }

    @Test("повторный вызов идемпотентен")
    func repeatedCallIsIdempotent() throws {
        let store = try TestStore.open()
        let shared = UUID()
        let first = Fixtures.exercise("A", in: store.context)
        let second = Fixtures.exercise("B", in: store.context)
        first.syncID = shared
        second.syncID = shared
        try store.context.save()

        DataIntegrity.deduplicateSyncIDs(context: store.context)
        let afterFirstRun = (first.syncID, second.syncID)

        DataIntegrity.deduplicateSyncIDs(context: store.context)

        #expect(first.syncID == afterFirstRun.0)
        #expect(second.syncID == afterFirstRun.1)
    }

    @Test("изменения действительно сохранены — проверка через новый ModelContext того же контейнера")
    func changesArePersisted() throws {
        let handle = try TestStore.open()
        let shared = UUID()
        let first = Fixtures.exercise("A", in: handle.context)
        let second = Fixtures.exercise("B", in: handle.context)
        first.syncID = shared
        second.syncID = shared
        try handle.context.save()

        DataIntegrity.deduplicateSyncIDs(context: handle.context)

        let reloaded = try handle.reload()
        let fetched = try reloaded.fetch(FetchDescriptor<Exercise>())
        let syncIDs = Set(fetched.map(\.syncID))
        #expect(syncIDs.count == 2)
    }
}

/// `DataIntegrity.restoreWorkoutComposition` backfills `WorkoutItem`s for
/// workouts that survive the `WorkoutTemplate`/`TemplateItem` removal with sets
/// but no plan — see FR-7 and technical-notes.md §7.2. `Workout.logSet` is called
/// directly rather than through `Workout.addExercise` to simulate the
/// pre-migration shape: sets linked to a workout that has no `WorkoutItem`s.
@Suite("DataIntegrity.restoreWorkoutComposition")
struct DataIntegrityRestoreCompositionTests {
    @Test("создаёт по одной плановой позиции на каждый залогированный подход, с его весом и повторами")
    func createsOneItemPerLoggedSet() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(in: store.context)
        workout.logSet(weight: 60, reps: 8, for: bench, context: store.context)
        workout.logSet(weight: 65, reps: 6, for: bench, context: store.context)

        DataIntegrity.restoreWorkoutComposition(context: store.context)

        let items = workout.sortedItems
        #expect(items.map(\.plannedWeight) == [60, 65])
        #expect(items.map(\.plannedReps) == [8, 6])
        #expect(items.map { $0.exercise?.persistentModelID } == [bench.persistentModelID, bench.persistentModelID])
    }

    @Test("упорядочивает упражнения по времени их первого подхода")
    func ordersExercisesByEarliestSet() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let squat = Fixtures.exercise("Присед", in: store.context)
        let workout = Fixtures.workout(in: store.context)
        let set1 = WorkoutSet(weight: 100, reps: 5, exercise: squat, workout: workout, createdAt: Fixtures.date(offset: 20))
        let set2 = WorkoutSet(weight: 60, reps: 8, exercise: bench, workout: workout, createdAt: Fixtures.date(offset: 10))
        store.context.insert(set1)
        store.context.insert(set2)
        workout.sets.append(contentsOf: [set1, set2])
        squat.sets.append(set1)
        bench.sets.append(set2)

        DataIntegrity.restoreWorkoutComposition(context: store.context)

        #expect(workout.orderedExercises.map(\.name) == ["Жим лёжа", "Присед"])
    }

    @Test("тренировку, у которой уже есть плановые позиции, не трогает")
    func doesNotTouchWorkoutsThatAlreadyHaveItems() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(items: [(bench, 60, 8)], in: store.context)
        let originalItemID = workout.items.first?.persistentModelID

        DataIntegrity.restoreWorkoutComposition(context: store.context)

        #expect(workout.items.count == 1)
        #expect(workout.items.first?.persistentModelID == originalItemID)
    }

    @Test("повторный вызов идемпотентен — не задваивает позиции")
    func repeatedCallIsIdempotent() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(in: store.context)
        workout.logSet(weight: 60, reps: 8, for: bench, context: store.context)

        DataIntegrity.restoreWorkoutComposition(context: store.context)
        DataIntegrity.restoreWorkoutComposition(context: store.context)

        #expect(workout.items.count == 1)
    }

    @Test("пустой стор не приводит к падению")
    func emptyStoreDoesNotCrash() throws {
        let store = try TestStore.open()
        DataIntegrity.restoreWorkoutComposition(context: store.context)
        #expect(try store.count(WorkoutItem.self) == 0)
    }

    @Test("тренировку без подходов и без позиций не трогает")
    func leavesEmptyWorkoutAlone() throws {
        let store = try TestStore.open()
        let workout = Fixtures.workout(in: store.context)

        DataIntegrity.restoreWorkoutComposition(context: store.context)

        #expect(workout.items.isEmpty)
    }

    @Test("восстановленные позиции сохранены — проверка через новый ModelContext того же контейнера")
    func changesArePersisted() throws {
        let handle = try TestStore.open()
        let bench = Fixtures.exercise(in: handle.context)
        let workout = Fixtures.workout(in: handle.context)
        workout.logSet(weight: 60, reps: 8, for: bench, context: handle.context)
        let syncID = workout.syncID

        DataIntegrity.restoreWorkoutComposition(context: handle.context)

        let reloaded = try handle.reload()
        let predicate = #Predicate<Workout> { $0.syncID == syncID }
        let workouts = try reloaded.fetch(FetchDescriptor<Workout>(predicate: predicate))
        let reloadedWorkout = try #require(workouts.first)
        #expect(reloadedWorkout.items.count == 1)
    }
}
