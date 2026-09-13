import Foundation
import Testing
import SwiftData
@testable import LiftLog

/// Inputs with explicit muscles, so a test states the muscle mapping instead of depending
/// on what the catalog says about a real exercise.
private func input(_ exercise: Exercise, primary: [String] = [], secondary: [String] = []) -> AnalyticsExercise {
    AnalyticsExercise(
        id: exercise.persistentModelID,
        name: exercise.name,
        primaryMuscles: primary,
        secondaryMuscles: secondary,
        samples: ExerciseStats.samples(for: exercise, calendar: Fixtures.utcCalendar)
    )
}

@Suite("TrainingAnalytics.summary")
struct TrainingAnalyticsSummaryTests {
    @Test("считает завершённые тренировки, подходы, объём и время только за период")
    func countsOnlyInsidePeriod() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let old = Fixtures.completedWorkout(bench, sets: [(50, 10)], on: Fixtures.day(0), in: store.context)
        let recent = Fixtures.completedWorkout(bench, sets: [(60, 8), (60, 8)], on: Fixtures.day(40), in: store.context)
        let interval = AnalyticsPeriod.month.interval(endingAt: Fixtures.day(45), calendar: Fixtures.utcCalendar)

        let summary = TrainingAnalytics.summary([input(bench)], [old, recent].compactMap { AnalyticsWorkout($0) }, in: interval)

        #expect(summary.workouts == 1)
        #expect(summary.sets == 2)
        #expect(summary.volume == 960)
        // `Fixtures.completedWorkout` finishes a minute after the last of its sets.
        #expect(summary.duration == 180)
    }

    @Test("идущая тренировка в сводку не попадает")
    func inProgressWorkoutIsExcluded() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let active = Fixtures.workout(date: Fixtures.day(44), startedAt: Fixtures.day(44), exercises: [bench], in: store.context)
        active.logSet(weight: 60, reps: 8, for: bench, now: Fixtures.day(44).addingTimeInterval(60), context: store.context)
        let interval = AnalyticsPeriod.month.interval(endingAt: Fixtures.day(45), calendar: Fixtures.utcCalendar)

        let summary = TrainingAnalytics.summary([input(bench)], [AnalyticsWorkout(active)].compactMap { $0 }, in: interval)

        #expect(summary.isEmpty)
        #expect(summary.volume == 0)
    }

    @Test("изменение к прошлому периоду — в целых процентах, без прошлого объёма его нет")
    func percentChange() {
        #expect(TrainingAnalytics.percentChange(from: 100, to: 92) == -8)
        #expect(TrainingAnalytics.percentChange(from: 80, to: 100) == 25)
        #expect(TrainingAnalytics.percentChange(from: 0, to: 50) == nil)
    }

    @Test("без завершённых тренировок и подходов вне тренировки истории нет")
    func noHistoryWithOnlyActiveWorkout() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        let active = Fixtures.workout(startedAt: Fixtures.epoch, exercises: [bench], in: store.context)
        active.logSet(weight: 60, reps: 8, for: bench, now: Fixtures.date(offset: 60), context: store.context)

        let snapshot = TrainingAnalytics.snapshot(exercises: [input(bench)], workouts: [], period: .month, now: Fixtures.day(1), calendar: Fixtures.utcCalendar)

        #expect(!snapshot.hasHistory)
    }
}

@Suite("TrainingAnalytics.volumeBuckets")
struct TrainingAnalyticsVolumeBucketsTests {
    @Test("недели начинаются с понедельника, пустые недели остаются нулями")
    func weeksStartOnMondayWithEmptyWeeks() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        // 2025-01-01 is a Wednesday: day 18 is Sunday 19 Jan, day 19 is Monday 20 Jan.
        Fixtures.completedWorkout(bench, sets: [(60, 10)], on: Fixtures.day(18), in: store.context)
        Fixtures.completedWorkout(bench, sets: [(100, 5)], on: Fixtures.day(19), in: store.context)

        let buckets = TrainingAnalytics.volumeBuckets([input(bench)], monthly: false, now: Fixtures.day(20), calendar: Fixtures.utcCalendar)

        #expect(buckets.count == 12)
        #expect(buckets.last?.start == Fixtures.day(19))
        #expect(buckets.last?.isCurrent == true)
        #expect(buckets.last?.volume == 500)
        #expect(buckets[10].start == Fixtures.day(12))
        #expect(buckets[10].volume == 600)
        #expect(buckets.prefix(10).allSatisfy { $0.volume == 0 })
    }

    @Test("для года — двенадцать месяцев, последний текущий")
    func yearUsesMonths() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        Fixtures.completedWorkout(bench, sets: [(60, 10)], on: Fixtures.day(5), in: store.context)

        let buckets = TrainingAnalytics.volumeBuckets([input(bench)], monthly: true, now: Fixtures.day(20), calendar: Fixtures.utcCalendar)
        let february2024 = try #require(Fixtures.utcCalendar.date(from: DateComponents(year: 2024, month: 2, day: 1)))

        #expect(buckets.count == 12)
        #expect(buckets.first?.start == february2024)
        #expect(buckets.last?.start == Fixtures.epoch)
        #expect(buckets.last?.volume == 600)
    }
}

@Suite("TrainingAnalytics — нагрузка мышц")
struct TrainingAnalyticsMuscleLoadTests {
    @Test("объём идёт основным мышцам целиком, вспомогательным — наполовину")
    func primaryFullSecondaryHalf() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        Fixtures.completedWorkout(bench, sets: [(100, 10)], on: Fixtures.day(1), in: store.context)
        let interval = AnalyticsPeriod.week.interval(endingAt: Fixtures.day(2), calendar: Fixtures.utcCalendar)

        let load = TrainingAnalytics.muscleLoad([input(bench, primary: ["chest"], secondary: ["triceps"])], in: interval)

        #expect(load.volume == ["chest": 1000, "triceps": 500])
        #expect(load.bodyweightMuscles.isEmpty)
    }

    @Test("общий регион атласа берёт нагрузку самой нагруженной мышцы, а не сумму")
    func sharedRegionTakesMax() throws {
        let store = try TestStore.open()
        let pulldown = Fixtures.exercise("Тяга блока", in: store.context)
        let row = Fixtures.exercise("Тяга в наклоне", in: store.context)
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        Fixtures.completedWorkout(pulldown, sets: [(40, 10)], on: Fixtures.day(1), in: store.context)
        Fixtures.completedWorkout(row, sets: [(10, 10)], on: Fixtures.day(1), in: store.context)
        Fixtures.completedWorkout(bench, sets: [(100, 10)], on: Fixtures.day(1), in: store.context)
        let interval = AnalyticsPeriod.week.interval(endingAt: Fixtures.day(2), calendar: Fixtures.utcCalendar)
        let load = TrainingAnalytics.muscleLoad([
            input(pulldown, primary: ["lats"]),
            input(row, primary: ["middle back"]),
            input(bench, primary: ["chest"]),
        ], in: interval)

        let intensities = TrainingAnalytics.slugIntensities(load)

        let upperBack = try #require(intensities["upper-back-left"])
        #expect(abs(upperBack - 0.4.squareRoot()) < 1e-9)
        #expect(intensities["chest-left"] == 1)
    }

    @Test("мышцы из упражнений без веса не попадают в «Мало нагружены»")
    func bodyweightMusclesAreNotUnderloaded() throws {
        let store = try TestStore.open()
        let pullUps = Fixtures.exercise("Подтягивания", in: store.context)
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        Fixtures.completedWorkout(pullUps, sets: [(0, 10)], on: Fixtures.day(1), in: store.context)
        Fixtures.completedWorkout(bench, sets: [(100, 10)], on: Fixtures.day(1), in: store.context)
        let interval = AnalyticsPeriod.week.interval(endingAt: Fixtures.day(2), calendar: Fixtures.utcCalendar)
        let load = TrainingAnalytics.muscleLoad([input(pullUps, primary: ["lats"]), input(bench, primary: ["chest"])], in: interval)

        let underloaded = TrainingAnalytics.underloadedMuscles(load)

        #expect(!underloaded.contains("lats"))
        #expect(!underloaded.contains("chest"))
        #expect(underloaded.contains("biceps"))
    }
}

@Suite("TrainingAnalytics — рекорды и тренды")
struct TrainingAnalyticsRecordsAndTrendsTests {
    @Test("рекорды за период — от новых к старым, без идущей тренировки")
    func recentRecordsNewestFirstWithoutInProgress() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        Fixtures.completedWorkout(bench, sets: [(60, 8)], on: Fixtures.day(0), in: store.context)
        Fixtures.completedWorkout(bench, sets: [(65, 5)], on: Fixtures.day(10), in: store.context)
        Fixtures.completedWorkout(bench, sets: [(70, 3)], on: Fixtures.day(20), in: store.context)
        let active = Fixtures.workout(date: Fixtures.day(21), startedAt: Fixtures.day(21), exercises: [bench], in: store.context)
        active.logSet(weight: 75, reps: 2, for: bench, now: Fixtures.day(21).addingTimeInterval(60), context: store.context)
        let interval = AnalyticsPeriod.month.interval(endingAt: Fixtures.day(22), calendar: Fixtures.utcCalendar)

        let records = TrainingAnalytics.recentRecords([input(bench)], in: interval)

        #expect(records.map { $0.weight } == [70, 65])
    }

    @Test("тренд сравнивает последнюю сессию с сессией месяц назад")
    func trendAgainstSessionMonthAgo() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        Fixtures.completedWorkout(bench, sets: [(60, 8)], on: Fixtures.day(0), in: store.context)
        Fixtures.completedWorkout(bench, sets: [(65, 5)], on: Fixtures.day(40), in: store.context)

        let trend = try #require(TrainingAnalytics.exerciseTrends([input(bench)], calendar: Fixtures.utcCalendar).first)

        #expect(trend.metric == .weight)
        #expect(trend.value == 65)
        #expect(trend.direction == .up)
    }

    @Test("без сессии месяц назад направления тренда нет")
    func noTrendWithoutOldEnoughSession() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise(in: store.context)
        Fixtures.completedWorkout(bench, sets: [(60, 8)], on: Fixtures.day(0), in: store.context)
        Fixtures.completedWorkout(bench, sets: [(65, 5)], on: Fixtures.day(10), in: store.context)

        let trend = try #require(TrainingAnalytics.exerciseTrends([input(bench)], calendar: Fixtures.utcCalendar).first)

        #expect(trend.direction == nil)
    }

    @Test("упражнение без веса показывает повторы")
    func bodyweightExerciseTrendsByReps() throws {
        let store = try TestStore.open()
        let pullUps = Fixtures.exercise("Подтягивания", in: store.context)
        Fixtures.completedWorkout(pullUps, sets: [(0, 8)], on: Fixtures.day(0), in: store.context)
        Fixtures.completedWorkout(pullUps, sets: [(0, 6)], on: Fixtures.day(40), in: store.context)

        let trend = try #require(TrainingAnalytics.exerciseTrends([input(pullUps)], calendar: Fixtures.utcCalendar).first)

        #expect(trend.metric == .reps)
        #expect(trend.value == 6)
        #expect(trend.direction == .down)
    }

    @Test("упражнения идут от недавно сделанных к давним")
    func trendsSortedByLastSession() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        let squat = Fixtures.exercise("Присед", in: store.context)
        Fixtures.completedWorkout(bench, sets: [(60, 8)], on: Fixtures.day(0), in: store.context)
        Fixtures.completedWorkout(squat, sets: [(100, 5)], on: Fixtures.day(3), in: store.context)

        let trends = TrainingAnalytics.exerciseTrends([input(bench), input(squat)], calendar: Fixtures.utcCalendar)

        #expect(trends.map { $0.name } == ["Присед", "Жим лёжа"])
    }
}
