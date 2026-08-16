import Testing
import Foundation
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

@Suite("Workout.addExercise")
struct WorkoutAddExerciseTests {
    @Test("повторное добавление того же упражнения создаёт вторую плановую позицию, а не дублирует ошибочно")
    func addingTwiceCreatesSecondPlannedPosition() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(in: store.context)

        workout.addExercise(bench, weight: 60, reps: 8, context: store.context)
        workout.addExercise(bench, weight: 65, reps: 6, context: store.context)

        #expect(workout.items.count == 2)
        #expect(workout.orderedExercises.count == 1)
        #expect(workout.sortedItems.map(\.plannedWeight) == [60, 65])
    }

    @Test("добавление без плановых цифр оставляет их nil")
    func addingWithoutNumbersLeavesThemNil() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(in: store.context)

        workout.addExercise(bench, context: store.context)

        #expect(workout.sortedItems.first?.plannedWeight == nil)
        #expect(workout.sortedItems.first?.plannedReps == nil)
    }

    @Test("два разных объекта с одинаковым именем добавляются оба — orderedExercises различает по идентичности")
    func differentObjectsSameNameBothAdded() throws {
        let store = try TestStore.open()
        let bench1 = Fixtures.exercise("Жим лёжа", in: store.context)
        let bench2 = Fixtures.exercise("Жим лёжа", in: store.context)
        let workout = Fixtures.workout(in: store.context)

        workout.addExercise(bench1, context: store.context)
        workout.addExercise(bench2, context: store.context)

        #expect(workout.orderedExercises.count == 2)
    }

    @Test("orderedExercises соответствует порядку добавления")
    func preservesInsertionOrder() throws {
        let store = try TestStore.open()
        let squat = Fixtures.exercise("Присед", in: store.context)
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let row = Fixtures.exercise("Тяга", in: store.context)
        let workout = Fixtures.workout(in: store.context)

        workout.addExercise(squat, context: store.context)
        workout.addExercise(bench, context: store.context)
        workout.addExercise(row, context: store.context)

        #expect(workout.orderedExercises.map(\.name) == ["Присед", "Жим лёжа", "Тяга"])
    }
}

@Suite("Workout.groupedItems / moveExercise / deleteExercise")
struct WorkoutGroupedItemsTests {
    @Test("groupedItems собирает позиции одного упражнения вместе, в порядке первого появления")
    func groupsPositionsByExercise() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let squat = Fixtures.exercise("Присед", in: store.context)
        let workout = Fixtures.workout(in: store.context)
        workout.addExercise(bench, weight: 60, reps: 8, context: store.context)
        workout.addExercise(squat, weight: 100, reps: 5, context: store.context)
        workout.addExercise(bench, weight: 65, reps: 6, context: store.context)

        let groups = workout.groupedItems

        #expect(groups.map(\.exercise.name) == ["Жим лёжа", "Присед"])
        #expect(groups[0].items.map(\.plannedWeight) == [60, 65])
    }

    @Test("moveExercise переставляет все позиции упражнения разом и перенумеровывает order сквозным счётчиком")
    func moveExerciseMovesWholeGroup() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let squat = Fixtures.exercise("Присед", in: store.context)
        let row = Fixtures.exercise("Тяга", in: store.context)
        let workout = Fixtures.workout(in: store.context)
        workout.addExercise(bench, weight: 60, reps: 8, context: store.context)
        workout.addExercise(squat, weight: 100, reps: 5, context: store.context)
        workout.addExercise(row, weight: 50, reps: 10, context: store.context)

        workout.moveExercise(from: IndexSet(integer: 2), to: 0)

        #expect(workout.groupedItems.map(\.exercise.name) == ["Тяга", "Жим лёжа", "Присед"])
        #expect(workout.sortedItems.map(\.order) == [0, 1, 2])
    }

    @Test("deleteExercise удаляет все плановые позиции упражнения и его залогированные подходы в этой тренировке")
    func deleteExerciseRemovesItemsAndSets() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let squat = Fixtures.exercise("Присед", in: store.context)
        let workout = Fixtures.workout(items: [(bench, 60, 8)], in: store.context)
        workout.addExercise(squat, weight: 100, reps: 5, context: store.context)
        Fixtures.log([(60, 8)], for: bench, in: workout, context: store.context)

        workout.deleteExercise(bench, context: store.context)

        #expect(workout.orderedExercises.map(\.name) == ["Присед"])
        #expect(workout.setsFor(bench).isEmpty)
    }

    @Test("deleteExercise не трогает позиции и подходы другого упражнения")
    func deleteExerciseLeavesOthersIntact() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let squat = Fixtures.exercise("Присед", in: store.context)
        let workout = Fixtures.workout(items: [(bench, 60, 8), (squat, 100, 5)], in: store.context)
        Fixtures.log([(100, 5)], for: squat, in: workout, context: store.context)

        workout.deleteExercise(bench, context: store.context)

        #expect(workout.orderedExercises.map(\.name) == ["Присед"])
        #expect(workout.setsFor(squat).count == 1)
    }
}

@Suite("Workout.logSet")
struct WorkoutLogSetTests {
    @Test("вставляет WorkoutSet в контекст и связывает его с тренировкой и упражнением (inverse-связи)")
    func linksBackToWorkoutAndExercise() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [bench], in: store.context)

        workout.logSet(weight: 60, reps: 8, for: bench, context: store.context)
        try store.context.save()

        let set = try #require(workout.sets.first)
        #expect(set.workout === workout)
        #expect(set.exercise === bench)
        #expect(bench.sets.contains(where: { $0.persistentModelID == set.persistentModelID }))
    }

    @Test("не проверяет вес и повторы — нулевые и отрицательные значения принимаются как есть")
    func acceptsNonPositiveValuesUnvalidated() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [bench], in: store.context)

        workout.logSet(weight: 0, reps: 0, for: bench, context: store.context)
        workout.logSet(weight: -10, reps: -5, for: bench, context: store.context)

        #expect(workout.setsFor(bench).map(\.weight) == [0, -10])
        #expect(workout.setsFor(bench).map(\.reps) == [0, -5])
    }
}

@Suite("Workout.setsFor")
struct WorkoutSetsForTests {
    @Test("возвращает только сеты запрошенного упражнения")
    func filtersByExercise() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let squat = Fixtures.exercise("Присед", in: store.context)
        let workout = Fixtures.workout(exercises: [bench, squat], in: store.context)

        Fixtures.log([(60, 8)], for: bench, in: workout, context: store.context)
        Fixtures.log([(100, 5)], for: squat, in: workout, context: store.context)

        #expect(workout.setsFor(bench).map(\.weight) == [60])
    }

    @Test("для упражнения, не входящего в тренировку, — пусто")
    func exerciseNotInWorkoutIsEmpty() throws {
        let store = try TestStore.open()
        let outsider = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(in: store.context)

        #expect(workout.setsFor(outsider).isEmpty)
    }
}

@Suite("Workout.isActive / start / finish — три состояния")
struct WorkoutLifecycleTests {
    @Test("план (startedAt == nil) не активен")
    func planIsNotActive() throws {
        let store = try TestStore.open()
        let workout = Fixtures.workout(startedAt: nil, in: store.context)
        #expect(workout.isActive == false)
    }

    @Test("start() проставляет startedAt, переносит date на момент старта и делает isActive истинным")
    func startActivatesWorkoutAndMovesDate() throws {
        let store = try TestStore.open()
        let workout = Fixtures.workout(date: Fixtures.date(offset: -1000), startedAt: nil, in: store.context)

        workout.start(now: Fixtures.date(offset: 5))

        #expect(workout.startedAt == Fixtures.date(offset: 5))
        #expect(workout.date == Fixtures.date(offset: 5))
        #expect(workout.isActive == true)
    }

    @Test("finish() проставляет completedAt и делает isActive ложным")
    func finishSetsCompletedAt() throws {
        let store = try TestStore.open()
        let workout = Fixtures.workout(in: store.context)

        workout.finish()

        #expect(workout.completedAt != nil)
        #expect(workout.isActive == false)
    }

    @Test("повторный finish() перезаписывает время завершения")
    func repeatedFinishOverwritesCompletedAt() throws {
        let store = try TestStore.open()
        let workout = Fixtures.workout(in: store.context)

        workout.finish(now: Fixtures.date(offset: 0))
        workout.finish(now: Fixtures.date(offset: 10))

        #expect(workout.completedAt == Fixtures.date(offset: 10))
    }
}

@Suite("Каскад удаления Workout -> WorkoutSet, WorkoutItem")
struct WorkoutDeleteCascadeTests {
    @Test("удаление тренировки удаляет все её сеты (проверка через fetchCount после save)")
    func deletingWorkoutCascadesToSets() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(exercises: [bench], in: store.context)
        Fixtures.log([(60, 8), (65, 6)], for: bench, in: workout, context: store.context)
        try store.context.save()

        #expect(try store.count(WorkoutSet.self) == 2)

        store.context.delete(workout)
        try store.context.save()

        #expect(try store.count(WorkoutSet.self) == 0)
    }

    @Test("удаление тренировки удаляет все её плановые позиции (проверка через fetchCount после save)")
    func deletingWorkoutCascadesToItems() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.workout(items: [(bench, 60, 8)], in: store.context)
        try store.context.save()

        #expect(try store.count(WorkoutItem.self) == 1)

        store.context.delete(workout)
        try store.context.save()

        #expect(try store.count(WorkoutItem.self) == 0)
    }
}

@Suite("Каскад удаления Exercise -> WorkoutSet")
struct ExerciseDeleteCascadeTests {
    @Test("удаление упражнения удаляет его подходы, а не оставляет их с exercise == nil")
    func deletingExerciseCascadesToSets() throws {
        let store = try TestStore.open()
        // Стоящее особняком упражнение, без Workout: `Workout.orderedExercises` строится
        // из `items`, так что подключение сюда ещё и тренировки задевало бы её отдельную
        // (нерелевантную здесь) семантику. Каскад, который проверяет этот тест, — только
        // Exercise -> WorkoutSet.
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        bench.addSet(weight: 60, reps: 8, context: store.context)
        bench.addSet(weight: 65, reps: 6, context: store.context)

        #expect(try store.count(WorkoutSet.self) == 2)

        store.context.delete(bench)
        try store.context.save()

        #expect(try store.count(WorkoutSet.self) == 0)
    }
}
