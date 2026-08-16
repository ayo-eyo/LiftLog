import Testing
import SwiftData
@testable import LiftLog

@Suite("WorkoutTemplate.addExercise / sortedItems")
struct WorkoutTemplateAddExerciseTests {
    @Test("назначает order = items.count и sortedItems отдаёт позиции по order")
    func assignsSequentialOrder() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let squat = Fixtures.exercise("Присед", in: store.context)
        let template = Fixtures.template(in: store.context)

        template.addExercise(bench, weight: 60, reps: 8, context: store.context)
        template.addExercise(squat, weight: 100, reps: 5, context: store.context)

        #expect(template.items.map(\.order) == [0, 1])
        #expect(template.sortedItems.map { $0.exercise?.name } == ["Жим лёжа", "Присед"])
    }
}

@Suite("Каскад удаления WorkoutTemplate -> TemplateItem")
struct WorkoutTemplateDeleteCascadeTests {
    @Test("удаление шаблона удаляет его TemplateItem")
    func deletingTemplateCascadesToItems() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let template = Fixtures.template(items: [(bench, 60, 8)], in: store.context)
        try store.context.save()

        #expect(try store.count(TemplateItem.self) == 1)

        store.context.delete(template)
        try store.context.save()

        #expect(try store.count(TemplateItem.self) == 0)
    }

    @Test("активная тренировка с этим шаблоном не ломается после его удаления — defaultWeight возвращает nil")
    func activeWorkoutSurvivesTemplateDeletion() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let template = Fixtures.template(items: [(bench, 60, 8)], in: store.context)
        let workout = Fixtures.workout(template: template, in: store.context)
        try store.context.save()

        #expect(workout.defaultWeight(for: bench) == 60)

        store.context.delete(template)
        try store.context.save()

        #expect(workout.isActive == true)
        #expect(workout.defaultWeight(for: bench) == nil)
        #expect(workout.defaultReps(for: bench) == nil)
    }
}

@Suite("WorkoutTemplate — валидация имени (текущее поведение, без валидации)")
struct WorkoutTemplateNameTests {
    @Test("пустое имя допускается")
    func emptyNameIsAccepted() throws {
        let store = try TestStore.open()
        let template = Fixtures.template(name: "", in: store.context)
        try store.context.save()

        #expect(template.name.isEmpty)
    }

    @Test("два шаблона с одинаковым именем сосуществуют без ошибки")
    func duplicateNamesCoexist() throws {
        let store = try TestStore.open()
        _ = Fixtures.template(name: "День груди", in: store.context)
        _ = Fixtures.template(name: "День груди", in: store.context)
        try store.context.save()

        #expect(try store.count(WorkoutTemplate.self) == 2)
    }
}
