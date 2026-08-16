import Testing
import SwiftData
@testable import LiftLog

@Suite("Workout.setsFor — порядок подходов")
struct WorkoutSetsForOrderTests {
    @Test("сохраняет порядок логирования, даже если createdAt совпадает")
    func stableOrderOnTiedTimestamps() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let workout = Fixtures.workout(exercises: [bench], in: store.context)

        // Одинаковый createdAt имитирует пачку команд с часов, доставленных почти
        // одновременно через transferUserInfo — единственный способ вызвать реальную
        // коллизию `sorted(by:)`, который не гарантированно стабилен.
        let tiedDate = Fixtures.date(offset: 10)
        for (weight, reps) in [(60.0, 8), (65.0, 6), (70.0, 4)] {
            let set = WorkoutSet(weight: weight, reps: reps, exercise: bench, workout: workout, createdAt: tiedDate, order: workout.sets.count)
            store.context.insert(set)
            workout.sets.append(set)
            bench.sets.append(set)
        }

        let sets = workout.setsFor(bench)
        #expect(sets.map(\.weight) == [60, 65, 70])
    }

    @Test("logSet назначает возрастающий order независимо от createdAt")
    func logSetAssignsMonotonicOrder() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let workout = Fixtures.workout(exercises: [bench], in: store.context)

        Fixtures.log([(60, 8), (65, 6), (70, 4)], for: bench, in: workout, context: store.context)

        let orders = workout.setsFor(bench).map(\.order)
        #expect(orders == orders.sorted())
        #expect(Set(orders).count == orders.count)
    }
}

@Suite("Каскад удаления Exercise -> WorkoutSet")
struct ExerciseDeleteCascadeTests {
    @Test("удаление упражнения удаляет его подходы, а не оставляет их с exercise == nil")
    func deletingExerciseCascadesToSets() throws {
        let store = try TestStore.open()
        // Стоящее особняком упражнение, без Workout: `Workout.exercises` — обычный
        // массив без @Relationship и без inverse, так что подключение сюда ещё и
        // тренировки задевало бы её отдельную (нерелевантную здесь) семантику.
        // Каскад, который проверяет этот тест, — только Exercise -> WorkoutSet.
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        bench.addSet(weight: 60, reps: 8, context: store.context)
        bench.addSet(weight: 65, reps: 6, context: store.context)

        #expect(try store.count(WorkoutSet.self) == 2)

        store.context.delete(bench)
        try store.context.save()

        #expect(try store.count(WorkoutSet.self) == 0)
    }
}
