import Testing
import SwiftData
@testable import LiftLog

/// `Workout.copy(of:)` — «повторить тренировку» без a separate template entity:
/// see FR-3 in plans/features/delete-fixture/requirements.md. The copy repeats the
/// source's plan verbatim; what was actually logged never leaks into it.
@Suite("Workout.copy — копия повторяет план источника")
struct WorkoutCopyTests {
    @Test("вес и повторы копии берутся из плана, а не из сделанных подходов")
    func copiesPlanNotLoggedSets() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let source = Fixtures.workout(items: [(bench, 100, 8), (bench, 100, 8), (bench, 100, 8)], in: store.context)
        Fixtures.log([(105, 6), (105, 6), (100, 5)], for: bench, in: source, context: store.context)
        source.finish()

        let copy = Workout.copy(of: source, sortIndex: 0, context: store.context)

        let items = copy.sortedItems.filter { $0.exercise?.persistentModelID == bench.persistentModelID }
        #expect(items.map(\.plannedWeight) == [100, 100, 100])
        #expect(items.map(\.plannedReps) == [8, 8, 8])
        #expect(copy.sets.isEmpty)
    }

    @Test("подходов в копии столько, сколько в плане, даже если сделано больше", arguments: [1, 3])
    func copyKeepsPlannedSetCount(loggedCount: Int) throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let source = Fixtures.workout(items: [(bench, 60, 8), (bench, 65, 6)], in: store.context)
        Fixtures.log(Array(repeating: (weight: 60.0, reps: 8), count: loggedCount), for: bench, in: source, context: store.context)

        let copy = Workout.copy(of: source, sortIndex: 0, context: store.context)

        let items = copy.sortedItems.filter { $0.exercise?.persistentModelID == bench.persistentModelID }
        #expect(items.map(\.plannedWeight) == [60, 65])
        #expect(items.map(\.plannedReps) == [8, 6])
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

    @Test("копирование идущей тренировки повторяет её план целиком, а не сделанную часть")
    func copyingActiveWorkoutCopiesWholePlan() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let source = Fixtures.workout(items: [(bench, 60, 8), (bench, 65, 6)], in: store.context)
        Fixtures.log([(60, 8)], for: bench, in: source, context: store.context)

        let copy = Workout.copy(of: source, sortIndex: 0, context: store.context)

        let items = copy.sortedItems.filter { $0.exercise?.persistentModelID == bench.persistentModelID }
        #expect(items.map(\.plannedWeight) == [60, 65])
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

    @Test("копия сохраняет имя источника без изменений")
    func copyKeepsSourceName() throws {
        let store = try TestStore.open()
        let source = Fixtures.workout(name: "День груди", in: store.context)

        let copy = Workout.copy(of: source, sortIndex: 0, context: store.context)

        #expect(copy.name == "День груди")
    }

    @Test("копия с позициями подменяет цифры упражнения, остальные копирует как есть")
    func copyWithPositionsReplacesNumbers() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let squat = Fixtures.exercise("Присед", in: store.context)
        let source = Fixtures.workout(items: [(bench, 60, 8), (bench, 60, 8), (squat, 100, 5)], in: store.context)

        let copy = Workout.copy(
            of: source,
            positions: [bench.persistentModelID: [ProgressionPosition(weight: 62.5, reps: 8), ProgressionPosition(weight: 62.5, reps: 7)]],
            sortIndex: 0,
            context: store.context
        )

        let items = copy.sortedItems
        #expect(items.map(\.plannedWeight) == [62.5, 62.5, 100])
        #expect(items.map(\.plannedReps) == [8, 7, 5])
        #expect(items.map(\.order) == [0, 1, 2])
        #expect(source.sortedItems.map(\.plannedWeight) == [60, 60, 100])
    }

    @Test("позиции сверх переданного списка копируются как есть, очищенное значение остаётся пустым")
    func copyWithShortPositionListKeepsTail() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let source = Fixtures.workout(items: [(bench, 60, 8), (bench, 65, 6)], in: store.context)

        let copy = Workout.copy(
            of: source,
            positions: [bench.persistentModelID: [ProgressionPosition(weight: nil, reps: 10)]],
            sortIndex: 0,
            context: store.context
        )

        #expect(copy.sortedItems.map(\.plannedWeight) == [nil, 65])
        #expect(copy.sortedItems.map(\.plannedReps) == [10, 6])
    }
}
