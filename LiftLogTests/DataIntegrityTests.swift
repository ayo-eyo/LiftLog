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
