import Testing
import SwiftData
@testable import LiftLog

/// `Workout.templateItem(for:)` → `defaultWeight`/`defaultReps` — позиционное
/// сопоставление залогированных сетов с позициями шаблона. Самая хрупкая логика
/// в проекте: индекс — это просто "сколько сетов этого упражнения уже залогировано".
@Suite("Workout.defaultWeight/defaultReps — позиционные дефолты из шаблона")
struct TemplateDefaultsTests {
    @Test("без шаблона оба дефолта — nil")
    func noTemplateMeansNoDefaults() throws {
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
        let template = Fixtures.template(items: [
            (bench, 60, 10),
            (bench, 70, 8),
            (bench, 80, 6),
        ], in: store.context)
        let workout = Fixtures.workout(template: template, in: store.context)

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

    @Test("упражнение встречается в шаблоне не подряд — берётся порядок sortedItems, а не соседство order")
    func nonConsecutivePositionsUseSortedOrder() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let squat = Fixtures.exercise("Присед", in: store.context)
        let template = Fixtures.template(in: store.context)
        // order 0, 1, 2 — bench появляется на позициях 0 и 2, squat между ними.
        template.addExercise(bench, weight: 60, reps: 10, context: store.context)
        template.addExercise(squat, weight: 100, reps: 5, context: store.context)
        template.addExercise(bench, weight: 65, reps: 8, context: store.context)
        let workout = Fixtures.workout(template: template, in: store.context)

        #expect(workout.defaultWeight(for: bench) == 60)
        workout.logSet(weight: 60, reps: 10, for: bench, context: store.context)
        #expect(workout.defaultWeight(for: bench) == 65)
    }

    @Test("упражнение, которого нет в шаблоне, даёт nil даже когда шаблон применён")
    func exerciseNotInTemplateGivesNil() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let extra = Fixtures.exercise("Разводка", in: store.context)
        let template = Fixtures.template(items: [(bench, 60, 10)], in: store.context)
        let workout = Fixtures.workout(exercises: [extra], template: template, in: store.context)

        #expect(workout.defaultWeight(for: extra) == nil)
        #expect(workout.defaultReps(for: extra) == nil)
    }

    @Test("удаление сета сдвигает индекс назад к предыдущей позиции")
    func deletingSetMovesIndexBack() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let template = Fixtures.template(items: [
            (bench, 60, 10),
            (bench, 70, 8),
        ], in: store.context)
        let workout = Fixtures.workout(template: template, in: store.context)

        workout.logSet(weight: 60, reps: 10, for: bench, context: store.context)
        #expect(workout.defaultWeight(for: bench) == 70)

        let loggedSet = workout.setsFor(bench)[0]
        store.context.delete(loggedSet)
        try store.context.save()

        #expect(workout.defaultWeight(for: bench) == 60)
    }

    @Test("позиция шаблона с удалённым упражнением (exercise == nil) не сдвигает индексацию остальных")
    func nilExercisePositionDoesNotShiftIndexing() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let template = Fixtures.template(in: store.context)
        template.addExercise(bench, weight: 60, reps: 10, context: store.context)

        let removable = Fixtures.exercise("Удалённое", in: store.context)
        template.addExercise(removable, weight: 999, reps: 999, context: store.context)
        // Simulates the exercise being deleted elsewhere: the TemplateItem survives
        // (no cascade from Exercise -> TemplateItem), its `exercise` link goes nil.
        template.items.last?.exercise = nil

        template.addExercise(bench, weight: 65, reps: 8, context: store.context)

        let workout = Fixtures.workout(template: template, in: store.context)
        #expect(workout.defaultWeight(for: bench) == 60)
        workout.logSet(weight: 60, reps: 10, for: bench, context: store.context)
        #expect(workout.defaultWeight(for: bench) == 65)
    }
}
