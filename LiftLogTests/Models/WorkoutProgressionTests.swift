import Foundation
import Testing
import SwiftData
@testable import LiftLog

private let settings = ProgressionSettings(weightStep: 2.5, repLimit: 12)

private func positions(_ values: [(Double?, Int?)]) -> [ProgressionPosition] {
    values.map { ProgressionPosition(weight: $0.0, reps: $0.1) }
}

/// The rule on plain values (plans/features/progression, FR-1).
@Suite("WorkoutProgression — правило прогрессии")
struct WorkoutProgressionRuleTests {
    @Test("план выполнен ровно — к весу каждой позиции прибавляется шаг, повторы те же")
    func exactlyFulfilledAddsStep() {
        let verdict = WorkoutProgression.progression(
            planned: positions([(60, 8), (60, 8), (65, 6)]),
            logged: [(60, 8), (60, 8), (65, 6)],
            settings: settings
        )

        #expect(verdict.isFulfilled)
        #expect(verdict.plannedVolume == 1350)
        #expect(verdict.loggedVolume == 1350)
        #expect(verdict.suggested == positions([(62.5, 8), (62.5, 8), (67.5, 6)]))
    }

    @Test("объём меньше планового — план не выполнен, позиции без изменений")
    func shortVolumeKeepsPlan() {
        let planned = positions([(60, 8), (60, 8)])

        let verdict = WorkoutProgression.progression(planned: planned, logged: [(60, 8), (60, 7)], settings: settings)

        #expect(!verdict.isFulfilled)
        #expect(verdict.suggested == planned)
    }

    @Test("лишние подходы идут в зачёт: меньше повторов в подходе, но больше подходов — выполнено")
    func extraSetsCount() {
        let verdict = WorkoutProgression.progression(
            planned: positions([(60, 8), (60, 8)]),
            logged: [(60, 6), (60, 6), (60, 6)],
            settings: settings
        )

        #expect(verdict.isFulfilled)
        #expect(verdict.loggedVolume == 1080)
    }

    @Test("собственный вес: объём — сумма повторов, прибавляется повтор в каждой позиции")
    func bodyweightAddsRep() {
        let verdict = WorkoutProgression.progression(
            planned: positions([(nil, 10), (0, 8)]),
            logged: [(0, 10), (0, 8)],
            settings: settings
        )

        #expect(verdict.isBodyweight)
        #expect(verdict.plannedVolume == 18)
        #expect(verdict.suggested == positions([(nil, 11), (0, 9)]))
    }

    @Test("собственный вес упирается в лимит: позиция на лимите не растёт, выше лимита не снижается")
    func bodyweightStopsAtLimit() {
        let verdict = WorkoutProgression.progression(
            planned: positions([(0, 11), (0, 12), (0, 15)]),
            logged: [(0, 11), (0, 12), (0, 15)],
            settings: settings
        )

        #expect(verdict.suggested == positions([(0, 12), (0, 12), (0, 15)]))
    }

    @Test("все позиции на лимите — предложения нет")
    func bodyweightAllAtLimitHasNoSuggestion() {
        let planned = positions([(0, 12), (0, 12)])

        let verdict = WorkoutProgression.progression(planned: planned, logged: [(0, 12), (0, 12)], settings: settings)

        #expect(verdict.isFulfilled)
        #expect(verdict.suggested == planned)
    }

    @Test("с весом лимит повторов не действует")
    func weightedIgnoresRepLimit() {
        let verdict = WorkoutProgression.progression(planned: positions([(40, 15)]), logged: [(40, 15)], settings: settings)

        #expect(verdict.suggested == positions([(42.5, 15)]))
    }

    @Test("в упражнении с весом позиция без веса не меняется")
    func weightlessPositionInWeightedExerciseIsUnchanged() {
        let verdict = WorkoutProgression.progression(
            planned: positions([(0, 10), (60, 8)]),
            logged: [(0, 10), (60, 8)],
            settings: settings
        )

        #expect(!verdict.isBodyweight)
        #expect(verdict.suggested == positions([(0, 10), (62.5, 8)]))
    }

    @Test("позиции без плановых повторов не участвуют и переносятся как есть")
    func positionsWithoutRepsAreCarriedOver() {
        let verdict = WorkoutProgression.progression(
            planned: positions([(60, 8), (70, nil)]),
            logged: [(60, 8)],
            settings: settings
        )

        #expect(verdict.plannedVolume == 480)
        #expect(verdict.suggested == positions([(62.5, 8), (70, nil)]))
    }

    @Test("упражнение без плановых цифр — не выполнено и без предложения, даже с подходами")
    func exerciseWithoutPlanHasNoVerdict() {
        let planned = positions([(nil, nil)])

        let verdict = WorkoutProgression.progression(planned: planned, logged: [(60, 8)], settings: settings)

        #expect(!verdict.isFulfilled)
        #expect(verdict.suggested == planned)
    }
}

/// The rule over a real workout: groups, order, sets and settings per exercise.
@Suite("WorkoutProgression — по тренировке")
struct WorkoutProgressionWorkoutTests {
    @Test("упражнения идут в порядке тренировки, каждое со своими подходами")
    func followsWorkoutOrder() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let pullUp = Fixtures.exercise("Подтягивания", in: store.context)
        let workout = Fixtures.workout(items: [(bench, 60, 8), (pullUp, nil, 10), (bench, 60, 8)], in: store.context)
        Fixtures.log([(60, 8), (60, 8)], for: bench, in: workout, context: store.context)
        Fixtures.log([(0, 9)], for: pullUp, in: workout, context: store.context)

        let result = WorkoutProgression.progressions(for: workout) { _ in settings }

        #expect(result.map(\.exercise.name) == ["Жим лёжа", "Подтягивания"])
        #expect(result[0].isFulfilled && result[0].hasSuggestion)
        #expect(result[0].suggested == positions([(62.5, 8), (62.5, 8)]))
        #expect(!result[1].isFulfilled && !result[1].hasSuggestion)
    }

    @Test("переопределение у упражнения важнее общих настроек")
    func exerciseOverrideWins() throws {
        let store = try TestStore.open()
        let dumbbell = Fixtures.exercise("Жим гантелей", in: store.context)
        dumbbell.progressionWeightStep = 2
        let pullUp = Fixtures.exercise("Подтягивания", in: store.context)
        pullUp.progressionRepLimit = 10
        let workout = Fixtures.workout(items: [(dumbbell, 20, 10), (pullUp, 0, 10)], in: store.context)
        Fixtures.log([(20, 10)], for: dumbbell, in: workout, context: store.context)
        Fixtures.log([(0, 10)], for: pullUp, in: workout, context: store.context)

        let result = WorkoutProgression.progressions(for: workout) { $0.progressionSettings(defaults: .standard) }

        #expect(result[0].suggested == positions([(22, 10)]))
        #expect(!result[1].hasSuggestion)
    }

    @Test("вердикт несёт настройки своего упражнения — экран по ним отмечает лимит")
    func progressionCarriesExerciseSettings() throws {
        let store = try TestStore.open()
        let pullUp = Fixtures.exercise("Подтягивания", in: store.context)
        pullUp.progressionRepLimit = 10
        let workout = Fixtures.workout(items: [(pullUp, 0, 10)], in: store.context)

        let result = WorkoutProgression.progressions(for: workout) { $0.progressionSettings(defaults: .standard) }

        #expect(result.first?.settings == ProgressionSettings(weightStep: 2.5, repLimit: 10))
    }

    @Test("экран прогрессии нужен, только если в тренировке есть позиция с плановыми повторами")
    func hasPlanNeedsPlannedReps() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let empty = Fixtures.workout(in: store.context)
        let withoutNumbers = Fixtures.workout(items: [(bench, nil, nil)], in: store.context)
        let planned = Fixtures.workout(items: [(bench, nil, nil), (bench, 60, 8)], in: store.context)

        #expect(!WorkoutProgression.hasPlan(empty))
        #expect(!WorkoutProgression.hasPlan(withoutNumbers))
        #expect(WorkoutProgression.hasPlan(planned))
    }

    @Test("пустая тренировка — пустой список")
    func emptyWorkout() throws {
        let store = try TestStore.open()
        let workout = Fixtures.workout(in: store.context)

        #expect(WorkoutProgression.progressions(for: workout) { _ in settings }.isEmpty)
    }
}

@Suite("ProgressionDefaults — общие настройки прогрессии")
struct ProgressionDefaultsTests {
    private func freshDefaults() throws -> UserDefaults {
        let name = "ProgressionDefaultsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("без сохранённых значений — 2,5 кг и 20 повторов")
    func defaultsWhenUnset() throws {
        #expect(ProgressionDefaults.load(try freshDefaults()) == ProgressionSettings(weightStep: 2.5, repLimit: 20))
    }

    @Test("сохранённые значения читаются обратно")
    func savedValuesLoad() throws {
        let defaults = try freshDefaults()

        ProgressionDefaults.save(ProgressionSettings(weightStep: 1.25, repLimit: 15), to: defaults)

        #expect(ProgressionDefaults.load(defaults) == ProgressionSettings(weightStep: 1.25, repLimit: 15))
    }

    @Test("значения вне диапазона и вне сетки 0,25 приводятся к допустимым")
    func outOfRangeIsClamped() {
        #expect(ProgressionSettings(weightStep: 0, repLimit: 0).clamped() == ProgressionSettings(weightStep: 0.25, repLimit: 1))
        #expect(ProgressionSettings(weightStep: 40, repLimit: 200).clamped() == ProgressionSettings(weightStep: 10, repLimit: 50))
        #expect(ProgressionSettings(weightStep: 2.3, repLimit: 20).clamped().weightStep == 2.25)
    }
}
