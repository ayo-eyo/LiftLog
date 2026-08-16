import Testing
import Foundation
import SwiftData
@testable import LiftLog

@Suite("Полный цикл сохранения через SwiftData")
struct PersistenceLifecycleTests {
    @Test("тренировка по шаблону → сеты → finish() → save() → новый контекст: всё на месте, связи целы")
    func fullLifecycleSurvivesReload() throws {
        let handle = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: handle.context)
        let template = Fixtures.template(items: [(bench, 60, 8)], in: handle.context)
        let workout = Fixtures.workout(template: template, in: handle.context)
        workout.logSet(weight: 60, reps: 8, for: bench, context: handle.context)
        workout.finish()

        let reloaded = try handle.reload()

        let workouts = try reloaded.fetch(FetchDescriptor<Workout>())
        let reloadedWorkout = try #require(workouts.first)
        #expect(reloadedWorkout.completedAt != nil)
        #expect(reloadedWorkout.exercises.map(\.name) == ["Жим лёжа"])
        #expect(reloadedWorkout.sets.count == 1)
        #expect(reloadedWorkout.sets.first?.exercise?.name == "Жим лёжа")
        #expect(reloadedWorkout.template?.name == template.name)
    }
}

@Suite("Предикат активной тренировки из RootTabView")
struct PersistenceActiveWorkoutPredicateTests {
    @Test("#Predicate<Workout> { completedAt == nil } находит только незавершённые")
    func predicateFindsOnlyIncompleteWorkouts() throws {
        let store = try TestStore.open()
        let active = Fixtures.workout(date: Fixtures.date(offset: 0), in: store.context)
        let finished = Fixtures.workout(date: Fixtures.date(offset: 100), in: store.context)
        finished.finish()
        try store.context.save()

        let predicate = #Predicate<Workout> { $0.completedAt == nil }
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

    @Test("WorkoutTemplate -> TemplateItem каскадно удаляется после save/reload")
    func templateCascadesToItemsAfterReload() throws {
        let handle = try TestStore.open()
        let bench = Fixtures.exercise(in: handle.context)
        let template = Fixtures.template(items: [(bench, 60, 8)], in: handle.context)
        _ = try handle.reload()

        handle.context.delete(template)
        try handle.context.save()

        #expect(try handle.count(TemplateItem.self) == 0)
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
