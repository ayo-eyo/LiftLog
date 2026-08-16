import Testing
import SwiftData
@testable import LiftLog

@Suite("WorkoutTemplate.addExercise — устойчивость order к удалениям")
struct TemplateOrderTests {
    @Test("после удаления позиции новая не коллизирует по order с оставшимися")
    func newItemDoesNotCollideWithSurvivorsAfterDelete() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let squat = Fixtures.exercise("Присед", in: store.context)
        let row = Fixtures.exercise("Тяга", in: store.context)

        let template = Fixtures.template(items: [
            (bench, 60, 8),
            (squat, 80, 5),
            (row, 50, 10),
        ], in: store.context)

        // order сейчас 0, 1, 2. Удаляем первую позицию (order 0), как делает
        // TemplateDetailView.deleteExercise — остаются order 1 и 2.
        let first = template.sortedItems[0]
        store.context.delete(first)

        // items.count теперь 2 — старый расчёт `order = items.count` дал бы 2,
        // что совпадает с уже существующей позицией (order 2).
        let pullUps = Fixtures.exercise("Подтягивания", in: store.context)
        template.addExercise(pullUps, weight: 0, reps: 10, context: store.context)

        let orders = template.items.map(\.order)
        #expect(Set(orders).count == orders.count, "order не должен повторяться: \(orders)")
    }

    @Test("sortedItems сохраняет порядок добавления при отсутствии удалений")
    func sortedItemsPreservesInsertionOrder() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let squat = Fixtures.exercise("Присед", in: store.context)

        let template = Fixtures.template(items: [
            (bench, 60, 8),
            (squat, 80, 5),
        ], in: store.context)

        #expect(template.sortedItems.map { $0.exercise?.name } == ["Жим лёжа", "Присед"])
    }
}
