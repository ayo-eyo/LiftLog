import Testing
import Foundation
import SwiftData
@testable import LiftLog

@Suite("Полный цикл сохранения через SwiftData")
struct PersistenceLifecycleTests {
    @Test("копия тренировки → старт → сеты → finish() → save() → новый контекст: всё на месте, связи целы")
    func fullLifecycleSurvivesReload() throws {
        let handle = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: handle.context)
        let source = Fixtures.workout(items: [(bench, 60, 8)], in: handle.context)

        let copy = Workout.copy(of: source, sortIndex: 0, context: handle.context)
        copy.start()
        copy.logSet(weight: 60, reps: 8, for: bench, context: handle.context)
        copy.finish()

        let reloaded = try handle.reload()

        let workouts = try reloaded.fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.date)]))
        let reloadedCopy = try #require(workouts.first { $0.syncID == copy.syncID })
        #expect(reloadedCopy.completedAt != nil)
        #expect(reloadedCopy.orderedExercises.map(\.name) == ["Жим лёжа"])
        #expect(reloadedCopy.sets.count == 1)
        #expect(reloadedCopy.sets.first?.exercise?.name == "Жим лёжа")
        // Плановые позиции копии повторяют план источника (у него не было залогированных
        // подходов), а не подходы, залогированные уже в самой копии.
        #expect(reloadedCopy.sortedItems.map(\.plannedWeight) == [60])
    }
}

@Suite("Предикат активной тренировки из RootTabView")
struct PersistenceActiveWorkoutPredicateTests {
    @Test("#Predicate<Workout> { startedAt != nil && completedAt == nil } находит только идущие, не планы и не завершённые")
    func predicateFindsOnlyActiveWorkouts() throws {
        let store = try TestStore.open()
        let plan = Fixtures.workout(date: Fixtures.date(offset: 0), startedAt: nil, in: store.context)
        let active = Fixtures.workout(date: Fixtures.date(offset: 50), in: store.context)
        let finished = Fixtures.workout(date: Fixtures.date(offset: 100), in: store.context)
        finished.finish()
        try store.context.save()
        _ = plan

        let predicate = #Predicate<Workout> { $0.startedAt != nil && $0.completedAt == nil }
        let found = try store.context.fetch(FetchDescriptor<Workout>(predicate: predicate))

        #expect(found.map(\.persistentModelID) == [active.persistentModelID])
    }
}

@Suite("Предикаты по syncID из WatchSessionManager работают на сохранённом сторе")
struct PersistenceSyncIDPredicateTests {
    @Test("поиск Workout по syncID находит объект после сохранения и перечитывания")
    func findsWorkoutBySyncIDAfterReload() throws {
        let handle = try TestStore.open()
        let workout = Fixtures.workout(in: handle.context)
        let syncID = workout.syncID

        let reloaded = try handle.reload()
        let predicate = #Predicate<Workout> { $0.syncID == syncID }
        let found = try reloaded.fetch(FetchDescriptor<Workout>(predicate: predicate))

        #expect(found.count == 1)
    }

    @Test("поиск Exercise по syncID находит объект после сохранения и перечитывания")
    func findsExerciseBySyncIDAfterReload() throws {
        let handle = try TestStore.open()
        let exercise = Fixtures.exercise(in: handle.context)
        let syncID = exercise.syncID

        let reloaded = try handle.reload()
        let predicate = #Predicate<Exercise> { $0.syncID == syncID }
        let found = try reloaded.fetch(FetchDescriptor<Exercise>(predicate: predicate))

        #expect(found.count == 1)
    }
}

@Suite("Каскады на сохранённом сторе")
struct PersistenceCascadeTests {
    @Test("Workout -> WorkoutSet каскадно удаляется после save/reload")
    func workoutCascadesToSetsAfterReload() throws {
        let handle = try TestStore.open()
        let bench = Fixtures.exercise(in: handle.context)
        let workout = Fixtures.workout(exercises: [bench], in: handle.context)
        Fixtures.log([(60, 8)], for: bench, in: workout, context: handle.context)
        _ = try handle.reload()

        handle.context.delete(workout)
        try handle.context.save()

        #expect(try handle.count(WorkoutSet.self) == 0)
    }

    @Test("Workout -> WorkoutItem каскадно удаляется после save/reload")
    func workoutCascadesToItemsAfterReload() throws {
        let handle = try TestStore.open()
        let bench = Fixtures.exercise(in: handle.context)
        let workout = Fixtures.workout(items: [(bench, 60, 8)], in: handle.context)
        _ = try handle.reload()

        #expect(try handle.count(WorkoutItem.self) == 1)

        handle.context.delete(workout)
        try handle.context.save()

        #expect(try handle.count(WorkoutItem.self) == 0)
    }

    @Test("Exercise -> WorkoutSet не каскадит по умолчанию отсутствия связи, но текущий контракт — удаление сетов")
    func exerciseDeletionCascadesToSetsAfterReload() throws {
        let handle = try TestStore.open()
        let bench = Fixtures.exercise(in: handle.context)
        bench.addSet(weight: 60, reps: 8, context: handle.context)
        _ = try handle.reload()

        handle.context.delete(bench)
        try handle.context.save()

        #expect(try handle.count(WorkoutSet.self) == 0)
    }
}

@Suite("LiftLogApp.schema строит контейнер целиком")
struct PersistenceSchemaTests {
    @Test("контейнер успешно строится по полной схеме приложения — регресс на модель, выпавшую из графа")
    func appSchemaBuildsContainerSuccessfully() throws {
        _ = try ModelContainer(
            for: LiftLogApp.schema,
            configurations: ModelConfiguration(schema: LiftLogApp.schema, isStoredInMemoryOnly: true)
        )
    }

    @Test("TestStore.schema перечисляет ровно те же модели, что LiftLogApp.schema")
    func testStoreSchemaMatchesAppSchema() {
        let appEntityNames = Set(LiftLogApp.schema.entities.map(\.name))
        let testEntityNames = Set(TestStore.schema.entities.map(\.name))
        #expect(appEntityNames == testEntityNames)
    }
}
