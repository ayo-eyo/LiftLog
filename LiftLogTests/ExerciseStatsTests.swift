import Foundation
import Testing
import SwiftData
@testable import LiftLog

@Suite("OneRepMax.estimate")
struct OneRepMaxTests {
    @Test("один повтор — это сам вес")
    func singleRepIsTheWeight() {
        #expect(OneRepMax.estimate(weight: 100, reps: 1) == 100)
    }

    @Test("формула Эпли работает до 12 повторов включительно")
    func epleyUpToTwelveReps() throws {
        let ten = try #require(OneRepMax.estimate(weight: 90, reps: 10))
        let twelve = try #require(OneRepMax.estimate(weight: 100, reps: 12))
        #expect(abs(ten - 120) < 1e-9)
        #expect(abs(twelve - 140) < 1e-9)
    }

    @Test("больше 12 повторов и подход без веса оценки не дают")
    func noEstimateBeyondTwelveRepsOrWithoutWeight() {
        #expect(OneRepMax.estimate(weight: 100, reps: 13) == nil)
        #expect(OneRepMax.estimate(weight: 0, reps: 5) == nil)
    }
}

@Suite("WeightRecord")
struct WeightRecordTests {
    @Test("без истории рекорда нет, строго больший вес — рекорд, равный — нет")
    func recordNeedsStrictlyHeavierThanExistingBest() {
        #expect(!WeightRecord.isRecord(weight: 60, best: nil))
        #expect(WeightRecord.isRecord(weight: 62.5, best: 60))
        #expect(!WeightRecord.isRecord(weight: 60, best: 60))
    }

    @Test("подход без веса не рекорд и планку не двигает")
    func bodyweightSetNeitherRecordsNorRaises() {
        #expect(!WeightRecord.isRecord(weight: 0, best: 60))
        #expect(WeightRecord.raising(60, with: 0) == 60)
        #expect(WeightRecord.raising(nil, with: 0) == nil)
        #expect(WeightRecord.raising(nil, with: 40) == 40)
        #expect(WeightRecord.raising(60, with: 55) == 60)
    }
}

@Suite("ExerciseStats — отметки рекордов веса")
struct ExerciseRecordMarksTests {
    private static func recordWeights(_ exercise: Exercise) -> [Double] {
        let samples = ExerciseStats.samples(for: exercise, calendar: Fixtures.utcCalendar)
        let records = ExerciseStats.recordSetIDs(samples)
        return samples.filter { records.contains($0.id) }.map(\.weight)
    }

    @Test("первый подход с весом не рекорд, следующий более тяжёлый — рекорд")
    func firstWeightedSetIsNotRecord() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        Fixtures.completedWorkout(bench, sets: [(60, 8), (65, 6)], in: store.context)

        #expect(Self.recordWeights(bench) == [65])
    }

    @Test("тот же вес на большее число повторов рекордом не считается")
    func sameWeightMoreRepsIsNotRecord() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        Fixtures.completedWorkout(bench, sets: [(60, 5), (60, 10)], in: store.context)

        #expect(Self.recordWeights(bench).isEmpty)
    }

    @Test("подход без веса между подходами с весом планку не сбрасывает")
    func bodyweightSetDoesNotResetTheBar() throws {
        let store = try TestStore.open()
        let dips = Fixtures.exercise("Отжимания на брусьях", in: store.context)
        Fixtures.completedWorkout(dips, sets: [(20, 8), (0, 12), (20, 8), (22.5, 5)], in: store.context)

        #expect(Self.recordWeights(dips) == [22.5])
    }

    @Test("рекорд считается по всей истории упражнения, в том числе после перерыва в год")
    func recordAcrossWorkoutsAndAfterLongBreak() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        Fixtures.completedWorkout(bench, sets: [(80, 5)], on: Fixtures.day(0), in: store.context)
        Fixtures.completedWorkout(bench, sets: [(75, 5), (82.5, 3)], on: Fixtures.day(400), in: store.context)

        #expect(Self.recordWeights(bench) == [82.5])
    }

    @Test("подходы вне тренировки участвуют в истории наравне с тренировками")
    func standaloneSetsCountTowardHistory() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        Fixtures.standaloneSet(weight: 70, reps: 5, for: bench, at: Fixtures.day(0), in: store.context)
        Fixtures.completedWorkout(bench, sets: [(70, 6), (72.5, 3)], on: Fixtures.day(1), in: store.context)

        #expect(Self.recordWeights(bench) == [72.5])
    }

    @Test("правка веса старого подхода снимает отметку рекорда с последующего")
    func editingEarlierSetRederivesLaterMarks() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.completedWorkout(bench, sets: [(60, 8), (65, 6)], in: store.context)
        let first = try #require(workout.setsFor(bench).first)

        first.weight = 70

        #expect(Self.recordWeights(bench).isEmpty)
    }

    @Test("удалённый подход в расчёт не попадает")
    func deletedSetIsIgnored() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let workout = Fixtures.completedWorkout(bench, sets: [(60, 8), (65, 6)], in: store.context)
        let first = try #require(workout.setsFor(bench).first)

        WorkoutSet.delete(first, context: store.context)

        #expect(Self.recordWeights(bench).isEmpty)
    }
}

@Suite("ExerciseStats.currentRecord")
struct ExerciseCurrentRecordTests {
    @Test("текущий рекорд — самый тяжёлый подход, при равном весе самый ранний")
    func heaviestEarliestSet() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        Fixtures.completedWorkout(bench, sets: [(80, 5)], on: Fixtures.day(0), in: store.context)
        Fixtures.completedWorkout(bench, sets: [(80, 8), (75, 10)], on: Fixtures.day(1), in: store.context)

        let record = try #require(ExerciseStats.currentRecord(ExerciseStats.samples(for: bench)))

        #expect(record.weight == 80)
        #expect(record.reps == 5)
        #expect(record.date == Fixtures.day(0).addingTimeInterval(60))
    }

    @Test("у упражнения, сделанного только без веса, рекорда нет")
    func noRecordForBodyweightOnly() throws {
        let store = try TestStore.open()
        let pullUps = Fixtures.exercise("Подтягивания", in: store.context)
        Fixtures.completedWorkout(pullUps, sets: [(0, 12), (0, 10)], in: store.context)

        #expect(ExerciseStats.currentRecord(ExerciseStats.samples(for: pullUps)) == nil)
    }
}

@Suite("ExerciseStats.sessions")
struct ExerciseSessionsTests {
    @Test("группирует подходы по тренировкам от новых к старым и считает объём")
    func groupsByWorkoutNewestFirst() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        Fixtures.completedWorkout(bench, sets: [(60, 8), (65, 6)], on: Fixtures.day(0), name: "Грудь", in: store.context)
        Fixtures.completedWorkout(bench, sets: [(70, 5)], on: Fixtures.day(2), name: "Жим", in: store.context)

        let sessions = ExerciseStats.sessions(ExerciseStats.samples(for: bench))

        #expect(sessions.map(\.workoutName) == ["Жим", "Грудь"])
        #expect(sessions[1].sets.map(\.weight) == [60, 65])
        #expect(sessions[1].volume == 60 * 8 + 65 * 6)
        #expect(sessions.allSatisfy { !$0.isStandalone })
    }

    @Test("подходы вне тренировки группируются по календарному дню")
    func standaloneSetsGroupByDay() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        Fixtures.standaloneSet(weight: 60, reps: 8, for: bench, at: Fixtures.day(0).addingTimeInterval(3_600), in: store.context)
        Fixtures.standaloneSet(weight: 62.5, reps: 6, for: bench, at: Fixtures.day(0).addingTimeInterval(7_200), in: store.context)
        Fixtures.standaloneSet(weight: 65, reps: 5, for: bench, at: Fixtures.day(1).addingTimeInterval(3_600), in: store.context)

        let sessions = ExerciseStats.sessions(ExerciseStats.samples(for: bench, calendar: Fixtures.utcCalendar))

        #expect(sessions.map { $0.sets.count } == [1, 2])
        #expect(sessions.allSatisfy { $0.isStandalone })
        #expect(sessions.allSatisfy { $0.workoutName == nil })
    }

    @Test("hasRecord отмечает только сессии с рекордным подходом")
    func hasRecordMarksOnlyRecordSessions() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        Fixtures.completedWorkout(bench, sets: [(60, 8)], on: Fixtures.day(0), in: store.context)
        Fixtures.completedWorkout(bench, sets: [(55, 8)], on: Fixtures.day(1), in: store.context)
        Fixtures.completedWorkout(bench, sets: [(62.5, 5)], on: Fixtures.day(2), in: store.context)

        let sessions = ExerciseStats.sessions(ExerciseStats.samples(for: bench))

        #expect(sessions.map(\.hasRecord) == [true, false, false])
    }
}

@Suite("ExerciseStats — точки графика")
struct ExerciseChartPointsTests {
    @Test("точки хронологические, только за период и только с значением метрики")
    func pointsFilteredByPeriodAndMetric() throws {
        let store = try TestStore.open()
        let dips = Fixtures.exercise("Отжимания на брусьях", in: store.context)
        Fixtures.completedWorkout(dips, sets: [(20, 8)], on: Fixtures.day(0), in: store.context)
        Fixtures.completedWorkout(dips, sets: [(0, 15)], on: Fixtures.day(100), in: store.context)
        Fixtures.completedWorkout(dips, sets: [(25, 5)], on: Fixtures.day(150), in: store.context)
        let sessions = ExerciseStats.sessions(ExerciseStats.samples(for: dips))
        let now = Fixtures.day(160)

        let recent = ExerciseStats.chartPoints(sessions, metric: .weight, period: .threeMonths, now: now, calendar: Fixtures.utcCalendar)
        let all = ExerciseStats.chartPoints(sessions, metric: .weight, period: .all, now: now, calendar: Fixtures.utcCalendar)

        #expect(recent.map(\.value) == [25])
        #expect(all.map(\.value) == [20, 25])
        #expect(all.map(\.hasRecord) == [false, true])
    }

    @Test("по умолчанию — все время, если за три месяца меньше двух тренировок")
    func defaultPeriodFallsBackToAll() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        Fixtures.completedWorkout(bench, sets: [(60, 8)], on: Fixtures.day(0), in: store.context)
        Fixtures.completedWorkout(bench, sets: [(65, 5)], on: Fixtures.day(150), in: store.context)
        let sessions = ExerciseStats.sessions(ExerciseStats.samples(for: bench))

        let period = ExerciseStats.defaultPeriod(sessions, metric: .weight, now: Fixtures.day(160), calendar: Fixtures.utcCalendar)

        #expect(period == .all)
    }

    @Test("по умолчанию — три месяца, если в них есть хотя бы две тренировки")
    func defaultPeriodIsThreeMonthsWithEnoughSessions() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        Fixtures.completedWorkout(bench, sets: [(60, 8)], on: Fixtures.day(0), in: store.context)
        Fixtures.completedWorkout(bench, sets: [(62.5, 5)], on: Fixtures.day(140), in: store.context)
        Fixtures.completedWorkout(bench, sets: [(65, 5)], on: Fixtures.day(150), in: store.context)
        let sessions = ExerciseStats.sessions(ExerciseStats.samples(for: bench))

        let period = ExerciseStats.defaultPeriod(sessions, metric: .weight, now: Fixtures.day(160), calendar: Fixtures.utcCalendar)

        #expect(period == .threeMonths)
    }

    @Test("упражнению без веса доступна только метрика повторов")
    func bodyweightOnlyHasRepsMetric() throws {
        let store = try TestStore.open()
        let pullUps = Fixtures.exercise("Подтягивания", in: store.context)
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        Fixtures.completedWorkout(pullUps, sets: [(0, 10)], in: store.context)
        Fixtures.completedWorkout(bench, sets: [(60, 8)], in: store.context)

        #expect(ExerciseStats.availableMetrics(ExerciseStats.samples(for: pullUps)) == [.reps])
        #expect(ExerciseStats.availableMetrics(ExerciseStats.samples(for: bench)) == [.weight, .oneRepMax, .volume])
    }
}

@Suite("ExerciseStats.lastSession")
struct ExerciseLastSessionTests {
    @Test("прошлый раз — последняя сессия до идущей тренировки, без неё самой")
    func latestSessionBeforeCurrentWorkout() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        Fixtures.completedWorkout(bench, sets: [(60, 8)], on: Fixtures.day(0), in: store.context)
        Fixtures.completedWorkout(bench, sets: [(62.5, 6), (62.5, 5)], on: Fixtures.day(3), in: store.context)
        let current = Fixtures.workout(date: Fixtures.day(5), startedAt: Fixtures.day(5), exercises: [bench], in: store.context)
        current.logSet(weight: 65, reps: 5, for: bench, now: Fixtures.day(5).addingTimeInterval(60), context: store.context)

        let last = try #require(ExerciseStats.lastSession(ExerciseStats.samples(for: bench), before: current))

        #expect(last.sets.map { $0.weight } == [62.5, 62.5])
        #expect(WorkoutExerciseLogView.setsSummary(last.sets) == "62,5×6 · 62,5×5")
    }

    @Test("без прошлых сессий прошлого раза нет")
    func noLastSessionWithoutHistory() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let current = Fixtures.workout(startedAt: Fixtures.epoch, exercises: [bench], in: store.context)
        current.logSet(weight: 60, reps: 8, for: bench, now: Fixtures.date(offset: 60), context: store.context)

        #expect(ExerciseStats.lastSession(ExerciseStats.samples(for: bench), before: current) == nil)
    }
}

@Suite("ExerciseStats.recordBeaten")
struct ExerciseRecordBeatenTests {
    @Test("рекордный подход сообщает свой вес и побитый прежний рекорд")
    func reportsWeightAndPreviousRecord() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        Fixtures.completedWorkout(bench, sets: [(80, 5)], on: Fixtures.day(0), in: store.context)
        let current = Fixtures.workout(date: Fixtures.day(1), startedAt: Fixtures.day(1), exercises: [bench], in: store.context)
        let set = current.logSet(weight: 82.5, reps: 3, for: bench, now: Fixtures.day(1).addingTimeInterval(60), context: store.context)

        let record = try #require(ExerciseStats.recordBeaten(by: set.persistentModelID, in: ExerciseStats.samples(for: bench)))

        #expect(record.weight == 82.5)
        #expect(record.previous == 80)
    }

    @Test("повтор только что поставленного рекорда баннера не даёт")
    func repeatingNewRecordIsNotRecord() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        Fixtures.completedWorkout(bench, sets: [(80, 5)], on: Fixtures.day(0), in: store.context)
        let current = Fixtures.workout(date: Fixtures.day(1), startedAt: Fixtures.day(1), exercises: [bench], in: store.context)
        current.logSet(weight: 82.5, reps: 3, for: bench, now: Fixtures.day(1).addingTimeInterval(60), context: store.context)
        let again = current.logSet(weight: 82.5, reps: 3, for: bench, now: Fixtures.day(1).addingTimeInterval(120), context: store.context)

        #expect(ExerciseStats.recordBeaten(by: again.persistentModelID, in: ExerciseStats.samples(for: bench)) == nil)
    }

    @Test("первый в истории подход с весом баннера не даёт")
    func firstWeightedSetIsNotRecord() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let current = Fixtures.workout(startedAt: Fixtures.epoch, exercises: [bench], in: store.context)
        let set = current.logSet(weight: 60, reps: 8, for: bench, now: Fixtures.date(offset: 60), context: store.context)

        #expect(ExerciseStats.recordBeaten(by: set.persistentModelID, in: ExerciseStats.samples(for: bench)) == nil)
    }
}

@Suite("ExerciseStats.records(in:)")
struct WorkoutRecordsSummaryTests {
    @Test("по упражнению — самый тяжёлый рекордный подход этой тренировки")
    func heaviestRecordPerExercise() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let squat = Fixtures.exercise("Присед", in: store.context)
        Fixtures.completedWorkout(bench, sets: [(60, 8)], on: Fixtures.day(0), in: store.context)
        Fixtures.completedWorkout(squat, sets: [(100, 5)], on: Fixtures.day(0), in: store.context)

        let day = Fixtures.day(1)
        let workout = Fixtures.workout(date: day, startedAt: day, exercises: [bench, squat], in: store.context)
        workout.logSet(weight: 62.5, reps: 5, for: bench, now: day.addingTimeInterval(60), context: store.context)
        workout.logSet(weight: 65, reps: 3, for: bench, now: day.addingTimeInterval(120), context: store.context)
        workout.logSet(weight: 95, reps: 5, for: squat, now: day.addingTimeInterval(180), context: store.context)
        workout.finish(now: day.addingTimeInterval(240))

        let records = ExerciseStats.records(in: workout)

        #expect(records.map { $0.exercise.name } == ["Жим лёжа"])
        #expect(records.map { $0.weight } == [65])
    }

    @Test("рекорд прошлой тренировки в сводку следующей не попадает")
    func earlierRecordStaysInItsWorkout() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        Fixtures.completedWorkout(bench, sets: [(60, 8)], on: Fixtures.day(0), in: store.context)
        Fixtures.completedWorkout(bench, sets: [(65, 5)], on: Fixtures.day(1), in: store.context)
        let latest = Fixtures.completedWorkout(bench, sets: [(62.5, 5)], on: Fixtures.day(2), in: store.context)

        #expect(ExerciseStats.records(in: latest).isEmpty)
    }
}
