import Testing
import SwiftData
@testable import LiftLog

@Suite("Exercise.catalogExercise / primaryMuscles / secondaryMuscles")
struct ExerciseCatalogLinkTests {
    @Test("резолвится по валидному catalogID")
    func resolvesValidCatalogID() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.catalogBackedExercise(in: store.context)

        #expect(exercise.catalogExercise != nil)
        #expect(exercise.catalogExercise?.id == "Barbell_Bench_Press_-_Medium_Grip")
    }

    @Test("nil при неизвестном catalogID")
    func nilForUnknownCatalogID() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(catalogID: "does-not-exist", in: store.context)

        #expect(exercise.catalogExercise == nil)
    }

    @Test("nil при catalogID == nil, и мышцы пусты для пользовательского упражнения")
    func nilForUserDefinedExercise() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise("Своё упражнение", in: store.context)

        #expect(exercise.catalogExercise == nil)
        #expect(exercise.primaryMuscles.isEmpty)
        #expect(exercise.secondaryMuscles.isEmpty)
    }

    @Test("primaryMuscles/secondaryMuscles берутся из каталога для привязанного упражнения")
    func musclesComeFromCatalog() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.catalogBackedExercise(in: store.context)
        let catalog = try #require(exercise.catalogExercise)

        #expect(exercise.primaryMuscles == catalog.primaryMuscles)
        #expect(exercise.secondaryMuscles == catalog.secondaryMuscles)
        #expect(!exercise.primaryMuscles.isEmpty)
    }
}

@Suite("Exercise.addSet")
struct ExerciseAddSetTests {
    @Test("вставляет сет в контекст и в sets")
    func insertsSetIntoContextAndSets() throws {
        let store = try TestStore.open()
        let exercise = Fixtures.exercise(in: store.context)

        exercise.addSet(weight: 60, reps: 8, context: store.context)
        try store.context.save()

        #expect(exercise.sets.count == 1)
        #expect(try store.count(WorkoutSet.self) == 1)
    }
}

@Suite("syncID — регресс на историческую коллизию default-value")
struct SyncIDUniquenessTests {
    @Test("два подряд созданных Exercise имеют разные syncID")
    func exercisesHaveDistinctSyncIDs() throws {
        let store = try TestStore.open()
        let first = Fixtures.exercise("A", in: store.context)
        let second = Fixtures.exercise("B", in: store.context)

        #expect(first.syncID != second.syncID)
    }

    @Test("два подряд созданных Workout имеют разные syncID")
    func workoutsHaveDistinctSyncIDs() throws {
        let store = try TestStore.open()
        let first = Fixtures.workout(in: store.context)
        let second = Fixtures.workout(in: store.context)

        #expect(first.syncID != second.syncID)
    }
}
