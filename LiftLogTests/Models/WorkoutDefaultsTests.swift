import Testing
import SwiftData
@testable import LiftLog

/// `Workout.plannedItem(for:)` → `defaultWeight`/`defaultReps` — позиционное
/// сопоставление залогированных сетов с плановыми позициями тренировки. Самая
/// хрупкая логика в проекте: индекс — это просто "сколько сетов этого
/// упражнения уже залогировано". Преемник `TemplateDefaultsTests` после того,
/// как план стал частью самой тренировки, а не отдельного шаблона.
@Suite("Workout.defaultWeight/defaultReps — позиционные дефолты из плана")
struct WorkoutDefaultsTests {
    @Test("без плановых позиций оба дефолта — nil")
    func noPlanMeansNoDefaults() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [bench], in: store.context)

        #expect(workout.defaultWeight(for: bench) == nil)
        #expect(workout.defaultReps(for: bench) == nil)
    }

    @Test("три позиции одного упражнения: индекс сдвигается по мере логирования, переработка сверх плана даёт nil")
    func threePositionsAdvanceThenNil() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(items: [
            (bench, 60, 10),
            (bench, 70, 8),
            (bench, 80, 6),
        ], in: store.context)

        #expect(workout.defaultWeight(for: bench) == 60)
        #expect(workout.defaultReps(for: bench) == 10)

        workout.logSet(weight: 60, reps: 10, for: bench, context: store.context)
        #expect(workout.defaultWeight(for: bench) == 70)
        #expect(workout.defaultReps(for: bench) == 8)

        workout.logSet(weight: 70, reps: 8, for: bench, context: store.context)
        #expect(workout.defaultWeight(for: bench) == 80)
        #expect(workout.defaultReps(for: bench) == 6)

        workout.logSet(weight: 80, reps: 6, for: bench, context: store.context)
        #expect(workout.defaultWeight(for: bench) == nil)
        #expect(workout.defaultReps(for: bench) == nil)
    }

    @Test("упражнение встречается в плане не подряд — берётся порядок sortedItems, а не соседство order")
    func nonConsecutivePositionsUseSortedOrder() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let squat = Fixtures.exercise("Присед", in: store.context)
        let workout = Fixtures.workout(in: store.context)
        // order 0, 1, 2 — bench появляется на позициях 0 и 2, squat между ними.
        workout.addExercise(bench, weight: 60, reps: 10, context: store.context)
        workout.addExercise(squat, weight: 100, reps: 5, context: store.context)
        workout.addExercise(bench, weight: 65, reps: 8, context: store.context)

        #expect(workout.defaultWeight(for: bench) == 60)
        workout.logSet(weight: 60, reps: 10, for: bench, context: store.context)
        #expect(workout.defaultWeight(for: bench) == 65)
    }

    @Test("упражнение, которого нет в плане тренировки, даёт nil, даже когда план не пуст")
    func exerciseNotInPlanGivesNil() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let extra = Fixtures.exercise("Разводка", in: store.context)
        let workout = Fixtures.workout(exercises: [extra], items: [(bench, 60, 10)], in: store.context)

        #expect(workout.defaultWeight(for: extra) == nil)
        #expect(workout.defaultReps(for: extra) == nil)
    }

    @Test("удаление сета сдвигает индекс назад к предыдущей позиции")
    func deletingSetMovesIndexBack() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(items: [
            (bench, 60, 10),
            (bench, 70, 8),
        ], in: store.context)

        workout.logSet(weight: 60, reps: 10, for: bench, context: store.context)
        #expect(workout.defaultWeight(for: bench) == 70)

        let loggedSet = workout.setsFor(bench)[0]
        store.context.delete(loggedSet)
        try store.context.save()

        #expect(workout.defaultWeight(for: bench) == 60)
    }

    @Test("позиция плана с удалённым упражнением (exercise == nil) не сдвигает индексацию остальных")
    func nilExercisePositionDoesNotShiftIndexing() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(in: store.context)
        workout.addExercise(bench, weight: 60, reps: 10, context: store.context)

        let removable = Fixtures.exercise("Удалённое", in: store.context)
        workout.addExercise(removable, weight: 999, reps: 999, context: store.context)
        // Simulates the exercise being deleted elsewhere: the WorkoutItem survives
        // (no cascade from Exercise -> WorkoutItem), its `exercise` link goes nil.
        workout.items.last?.exercise = nil

        workout.addExercise(bench, weight: 65, reps: 8, context: store.context)

        #expect(workout.defaultWeight(for: bench) == 60)
        workout.logSet(weight: 60, reps: 10, for: bench, context: store.context)
        #expect(workout.defaultWeight(for: bench) == 65)
    }

    @Test("плановая позиция без цифр (добавлена по ходу) не подставляет 0 — дефолт падает на следующий приоритет")
    func plannedPositionWithoutNumbersFallsThrough() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(in: store.context)
        workout.addExercise(bench, context: store.context)

        #expect(workout.defaultWeight(for: bench) == nil)
        #expect(workout.defaultReps(for: bench) == nil)
    }
}
