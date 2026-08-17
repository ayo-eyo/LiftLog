import Testing
import SwiftData
@testable import LiftLog

/// `Workout.copy(of:)` — «повторить тренировку» без a separate template entity:
/// see FR-3 in plans/features/delete-fixture/requirements.md.
@Suite("Workout.copy — план из подходов или из плана источника")
struct WorkoutCopyTests {
    @Test("если у упражнения источника есть залогированные подходы, они становятся планом копии")
    func copiesLoggedSetsAsPlan() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let source = Fixtures.workout(exercises: [bench], in: store.context)
        Fixtures.log([(100, 5), (100, 5), (100, 5)], for: bench, in: source, context: store.context)

        let copy = Workout.copy(of: source, sortIndex: 0, context: store.context)

        let items = copy.sortedItems.filter { $0.exercise?.persistentModelID == bench.persistentModelID }
        #expect(items.map(\.plannedWeight) == [100, 100, 100])
        #expect(items.map(\.plannedReps) == [5, 5, 5])
        #expect(copy.sets.isEmpty)
    }

    @Test("если подходов нет, план копии повторяет план источника")
    func copiesSourcePlanWhenNoLoggedSets() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let source = Fixtures.workout(items: [(bench, 60, 8), (bench, 65, 6)], in: store.context)

        let copy = Workout.copy(of: source, sortIndex: 0, context: store.context)

        let items = copy.sortedItems.filter { $0.exercise?.persistentModelID == bench.persistentModelID }
        #expect(items.map(\.plannedWeight) == [60, 65])
        #expect(items.map(\.plannedReps) == [8, 6])
    }

    @Test("копия получает новый syncID, отличный от источника")
    func copyGetsNewSyncID() throws {
        let store = try TestStore.open()
        let source = Fixtures.workout(in: store.context)

        let copy = Workout.copy(of: source, sortIndex: 0, context: store.context)

        #expect(copy.syncID != source.syncID)
    }

    @Test("копия создаётся в состоянии план: startedAt и completedAt равны nil")
    func copyIsAPlan() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let source = Fixtures.workout(exercises: [bench], in: store.context)
        Fixtures.log([(60, 8)], for: bench, in: source, context: store.context)
        source.finish()

        let copy = Workout.copy(of: source, sortIndex: 0, context: store.context)

        #expect(copy.startedAt == nil)
        #expect(copy.completedAt == nil)
        #expect(copy.isActive == false)
    }

    @Test("копирование не мутирует источник")
    func sourceIsUnchanged() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let source = Fixtures.workout(items: [(bench, 60, 8)], in: store.context)
        Fixtures.log([(60, 8)], for: bench, in: source, context: store.context)
        let originalItemCount = source.items.count
        let originalSetCount = source.sets.count

        _ = Workout.copy(of: source, sortIndex: 0, context: store.context)

        #expect(source.items.count == originalItemCount)
        #expect(source.sets.count == originalSetCount)
    }

    @Test("копия копии работает и не хранит ссылку на исходный источник")
    func copyOfCopyWorks() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let source = Fixtures.workout(items: [(bench, 60, 8)], in: store.context)

        let firstCopy = Workout.copy(of: source, sortIndex: 0, context: store.context)
        let secondCopy = Workout.copy(of: firstCopy, sortIndex: -1, context: store.context)

        let items = secondCopy.sortedItems.filter { $0.exercise?.persistentModelID == bench.persistentModelID }
        #expect(items.map(\.plannedWeight) == [60])
        #expect(secondCopy.syncID != firstCopy.syncID)
        #expect(secondCopy.syncID != source.syncID)
    }

    @Test("копирование пустой тренировки даёт пустую копию без ошибок")
    func copyingEmptyWorkoutGivesEmptyCopy() throws {
        let store = try TestStore.open()
        let source = Fixtures.workout(in: store.context)

        let copy = Workout.copy(of: source, sortIndex: 0, context: store.context)

        #expect(copy.items.isEmpty)
        #expect(copy.sets.isEmpty)
    }

    @Test("копирование идущей тренировки: уже сделанные подходы становятся планом копии")
    func copyingActiveWorkoutUsesLoggedSetsAsPlan() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let source = Fixtures.workout(items: [(bench, 60, 8), (bench, 65, 6)], in: store.context)
        Fixtures.log([(60, 8)], for: bench, in: source, context: store.context)

        let copy = Workout.copy(of: source, sortIndex: 0, context: store.context)

        let items = copy.sortedItems.filter { $0.exercise?.persistentModelID == bench.persistentModelID }
        #expect(items.map(\.plannedWeight) == [60])
    }

    @Test("Exercise не дублируется — копия ссылается на тот же объект, что и источник")
    func copyReusesSameExerciseObjects() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let source = Fixtures.workout(items: [(bench, 60, 8)], in: store.context)

        let copy = Workout.copy(of: source, sortIndex: 0, context: store.context)

        #expect(copy.orderedExercises.first?.persistentModelID == bench.persistentModelID)
        #expect(try store.count(Exercise.self) == 1)
    }

    @Test("название копии получает пометку, пустое имя источника остаётся пустым")
    func copyNameMarksCopyUnlessSourceNameIsEmpty() {
        #expect(Workout.copyName(of: "День груди") == "День груди (копия)")
        #expect(Workout.copyName(of: "") == "")
    }
}
