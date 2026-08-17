import Testing
import Foundation
import SwiftData
@testable import LiftLog

@Suite("Workout.addExercise — устойчивость order к удалениям")
struct WorkoutItemOrderTests {
    @Test("после удаления позиции новая не коллизирует по order с оставшимися")
    func newItemDoesNotCollideWithSurvivorsAfterDelete() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let squat = Fixtures.exercise("Присед", in: store.context)
        let row = Fixtures.exercise("Тяга", in: store.context)

        let workout = Fixtures.workout(items: [
            (bench, 60, 8),
            (squat, 80, 5),
            (row, 50, 10),
        ], in: store.context)

        // order сейчас 0, 1, 2. Удаляем первую позицию (order 0), как делает
        // WorkoutDetailView.deleteExercise — остаются order 1 и 2.
        let first = workout.sortedItems[0]
        store.context.delete(first)

        // items.count теперь 2 — старый расчёт `order = items.count` дал бы 2,
        // что совпадает с уже существующей позицией (order 2).
        let pullUps = Fixtures.exercise("Подтягивания", in: store.context)
        workout.addExercise(pullUps, weight: 0, reps: 10, context: store.context)

        let orders = workout.items.map(\.order)
        #expect(Set(orders).count == orders.count, "order не должен повторяться: \(orders)")
    }

    @Test("sortedItems сохраняет порядок добавления при отсутствии удалений")
    func sortedItemsPreservesInsertionOrder() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let squat = Fixtures.exercise("Присед", in: store.context)

        let workout = Fixtures.workout(items: [
            (bench, 60, 8),
            (squat, 80, 5),
        ], in: store.context)

        #expect(workout.sortedItems.map { $0.exercise?.name } == ["Жим лёжа", "Присед"])
    }
}

@Suite("Перестановка упражнений внутри тренировки переживает save()/перечитывание")
struct WorkoutMoveExercisePersistenceTests {
    @Test("порядок после moveExercise сохраняется и виден в новом контексте")
    func orderSurvivesReload() throws {
        let handle = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: handle.context)
        let squat = Fixtures.exercise("Присед", in: handle.context)
        let row = Fixtures.exercise("Тяга", in: handle.context)
        let workout = Fixtures.workout(items: [(bench, 60, 8), (squat, 100, 5), (row, 50, 10)], in: handle.context)

        workout.moveExercise(from: IndexSet(integer: 2), to: 0)

        let reloaded = try handle.reload()
        let reloadedWorkout = try #require(try reloaded.fetch(FetchDescriptor<Workout>()).first)

        #expect(reloadedWorkout.groupedItems.map(\.exercise.name) == ["Тяга", "Жим лёжа", "Присед"])
    }
}

@Suite("WorkoutListView.reorder / topSortIndex — ручной порядок списка")
struct WorkoutListOrderingTests {
    @Test("до первой перестановки все sortIndex равны 0, список сортируется по дате")
    func defaultSortIndexIsZero() throws {
        let store = try TestStore.open()
        let workout = Fixtures.workout(in: store.context)
        #expect(workout.sortIndex == 0)
    }

    @Test("reorder нумерует видимый список по текущему порядку, затем применяет перестановку")
    func reorderRenumbersThenMoves() throws {
        let store = try TestStore.open()
        let a = Fixtures.workout(date: Fixtures.date(offset: 0), in: store.context)
        let b = Fixtures.workout(date: Fixtures.date(offset: 1), in: store.context)
        let c = Fixtures.workout(date: Fixtures.date(offset: 2), in: store.context)

        WorkoutListView.reorder([a, b, c], from: IndexSet(integer: 2), to: 0)

        #expect([c, a, b].map(\.sortIndex) == [0, 1, 2])
    }

    @Test("topSortIndex встаёт выше минимального существующего sortIndex")
    func topSortIndexIsBelowMinimum() throws {
        let store = try TestStore.open()
        let a = Fixtures.workout(sortIndex: -3, in: store.context)
        let b = Fixtures.workout(sortIndex: 5, in: store.context)

        #expect(WorkoutListView.topSortIndex(among: [a, b]) == -4)
    }

    @Test("topSortIndex для пустого списка — -1, не 0, чтобы не совпасть с дефолтом остальных")
    func topSortIndexForEmptyListIsNegativeOne() throws {
        #expect(WorkoutListView.topSortIndex(among: []) == -1)
    }
}
