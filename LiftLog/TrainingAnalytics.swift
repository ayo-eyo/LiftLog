import Foundation
import SwiftData

/// One exercise's inputs for the Analytics tab, snapshotted off the model once per refresh
/// so the aggregates below are plain value code.
struct AnalyticsExercise {
    let id: PersistentIdentifier
    let name: String
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    /// The whole history (`ExerciseStats.samples`), the running workout included so record
    /// marks agree with the progress screen. Every aggregate skips in-progress sets.
    let samples: [SetSample]
}

extension AnalyticsExercise {
    init(_ exercise: Exercise) {
        self.init(
            id: exercise.persistentModelID,
            name: exercise.name,
            primaryMuscles: exercise.primaryMuscles,
            secondaryMuscles: exercise.secondaryMuscles,
            samples: ExerciseStats.samples(for: exercise)
        )
    }
}

struct AnalyticsWorkout: Equatable {
    /// When it started (`Workout.start` moves `date` there).
    let date: Date
    let duration: TimeInterval
}

extension AnalyticsWorkout {
    /// nil unless the workout is finished — only finished workouts are analysed (decision 8).
    init?(_ workout: Workout) {
        guard let started = workout.startedAt, let completed = workout.completedAt else { return nil }
        self.init(date: workout.date, duration: max(0, completed.timeIntervalSince(started)))
    }
}

enum AnalyticsPeriod: String, CaseIterable, Identifiable {
    case week, month, threeMonths, year

    var id: Self { self }

    var title: String {
        switch self {
        case .week: "Неделя"
        case .month: "Месяц"
        case .threeMonths: "3 мес"
        case .year: "Год"
        }
    }

    /// A rolling window ending at `now` — «Месяц» is the last month, not the calendar month
    /// so far — so it compares like-for-like with the same window right before it.
    func interval(endingAt now: Date, calendar: Calendar) -> DateInterval {
        let start: Date?
        switch self {
        case .week: start = calendar.date(byAdding: .day, value: -7, to: now)
        case .month: start = calendar.date(byAdding: .month, value: -1, to: now)
        case .threeMonths: start = calendar.date(byAdding: .month, value: -3, to: now)
        case .year: start = calendar.date(byAdding: .year, value: -1, to: now)
        }
        return DateInterval(start: start ?? now, end: now)
    }
}

struct PeriodSummary: Equatable {
    var workouts = 0
    var sets = 0
    var volume: Double = 0
    var duration: TimeInterval = 0

    var isEmpty: Bool { workouts == 0 && sets == 0 }
}

struct VolumeBucket: Identifiable, Equatable {
    let start: Date
    let volume: Double
    /// The week (month) still under way — drawn as incomplete.
    let isCurrent: Bool

    var id: Date { start }
}

struct MuscleLoad: Equatable {
    /// Catalog muscle name (`"chest"`, `"lats"`) → volume credited to it.
    var volume: [String: Double] = [:]
    /// Muscles worked by bodyweight sets, which carry no volume (decision 19).
    var bodyweightMuscles: Set<String> = []
}

struct AnalyticsRecord: Identifiable, Equatable {
    /// The record set.
    let id: PersistentIdentifier
    let exerciseID: PersistentIdentifier
    let exerciseName: String
    let weight: Double
    let date: Date
}

struct ExerciseTrend: Identifiable, Equatable {
    enum Direction: Equatable { case up, down, flat }

    let exerciseID: PersistentIdentifier
    let name: String
    let lastDate: Date
    /// `.weight`, or `.reps` for an exercise only ever done without weight.
    let metric: ExerciseProgressMetric
    /// The latest session's value for `metric`; nil when that session has none (a
    /// bodyweight session of a weighted exercise).
    let value: Double?
    /// Against the latest session at least a month older; nil when there's none.
    let direction: Direction?

    var id: PersistentIdentifier { exerciseID }
}

struct AnalyticsSnapshot {
    /// Anything finished at all — otherwise the tab shows its empty state.
    let hasHistory: Bool
    let summary: PeriodSummary
    let previousSummary: PeriodSummary
    let volumeBuckets: [VolumeBucket]
    let bucketsAreMonthly: Bool
    let muscleLoad: MuscleLoad
    let intensities: [String: Double]
    let underloaded: [String]
    let records: [AnalyticsRecord]
    let trends: [ExerciseTrend]
}

/// Everything on the Analytics tab (plans/features/progress-analytics, FR-5), derived from
/// finished workouts and sets logged outside a workout. Pure functions over snapshots:
/// `Calendar` and `now` are parameters, so week boundaries are testable in a fixed time zone.
enum TrainingAnalytics {
    static let underloadThreshold = 0.2

    static func snapshot(
        exercises: [AnalyticsExercise],
        workouts: [AnalyticsWorkout],
        period: AnalyticsPeriod,
        now: Date,
        calendar: Calendar
    ) -> AnalyticsSnapshot {
        let interval = period.interval(endingAt: now, calendar: calendar)
        let previous = period.interval(endingAt: interval.start, calendar: calendar)
        let load = muscleLoad(exercises, in: interval)
        return AnalyticsSnapshot(
            hasHistory: !workouts.isEmpty || exercises.contains { $0.samples.contains { !$0.inProgress } },
            summary: summary(exercises, workouts, in: interval),
            previousSummary: summary(exercises, workouts, in: previous),
            volumeBuckets: volumeBuckets(exercises, monthly: period == .year, now: now, calendar: calendar),
            bucketsAreMonthly: period == .year,
            muscleLoad: load,
            intensities: slugIntensities(load),
            underloaded: underloadedMuscles(load),
            records: recentRecords(exercises, in: interval),
            trends: exerciseTrends(exercises, calendar: calendar)
        )
    }

    /// Half-open on the left, so a set exactly on the boundary between a period and the one
    /// before it isn't counted in both.
    static func isInside(_ date: Date, _ interval: DateInterval) -> Bool {
        date > interval.start && date <= interval.end
    }

    static func summary(_ exercises: [AnalyticsExercise], _ workouts: [AnalyticsWorkout], in interval: DateInterval) -> PeriodSummary {
        var result = PeriodSummary()
        for workout in workouts where isInside(workout.date, interval) {
            result.workouts += 1
            result.duration += workout.duration
        }
        for exercise in exercises {
            for sample in exercise.samples where !sample.inProgress && isInside(sample.date, interval) {
                result.sets += 1
                result.volume += sample.weight * Double(sample.reps)
            }
        }
        return result
    }

    /// Whole percent change; nil when there's nothing to compare against.
    static func percentChange(from previous: Double, to current: Double) -> Int? {
        guard previous > 0 else { return nil }
        return Int(((current - previous) / previous * 100).rounded())
    }

    /// The last `count` weeks (or months), oldest first, empty ones included as zero so the
    /// chart doesn't close up gaps. Weeks start on Monday whatever the calendar says
    /// (decision 9).
    static func volumeBuckets(
        _ exercises: [AnalyticsExercise],
        monthly: Bool,
        count: Int = 12,
        now: Date,
        calendar: Calendar
    ) -> [VolumeBucket] {
        var calendar = calendar
        calendar.firstWeekday = 2
        let component: Calendar.Component = monthly ? .month : .weekOfYear
        guard let current = calendar.dateInterval(of: component, for: now)?.start else { return [] }
        let starts = (0..<count).reversed().compactMap { calendar.date(byAdding: component, value: -$0, to: current) }
        guard let first = starts.first else { return [] }

        var volumes = Array(repeating: 0.0, count: starts.count)
        for exercise in exercises {
            for sample in exercise.samples where !sample.inProgress && sample.date >= first {
                // Binary search over the few sorted boundaries instead of asking `Calendar`
                // for the week of each of possibly tens of thousands of sets.
                var low = 0
                var high = starts.count - 1
                while low < high {
                    let mid = (low + high + 1) / 2
                    if starts[mid] <= sample.date { low = mid } else { high = mid - 1 }
                }
                volumes[low] += sample.weight * Double(sample.reps)
            }
        }
        return starts.enumerated().map { index, start in
            VolumeBucket(start: start, volume: volumes[index], isCurrent: index == starts.count - 1)
        }
    }

    /// Volume per muscle (decision 13): a set's weight × reps goes to the exercise's primary
    /// muscles in full and to its secondary ones by half.
    static func muscleLoad(_ exercises: [AnalyticsExercise], in interval: DateInterval) -> MuscleLoad {
        var load = MuscleLoad()
        for exercise in exercises {
            for sample in exercise.samples where !sample.inProgress && isInside(sample.date, interval) {
                if sample.weight > 0 {
                    let volume = sample.weight * Double(sample.reps)
                    for muscle in exercise.primaryMuscles {
                        load.volume[muscle, default: 0] += volume
                    }
                    for muscle in exercise.secondaryMuscles {
                        load.volume[muscle, default: 0] += volume / 2
                    }
                } else {
                    load.bodyweightMuscles.formUnion(exercise.primaryMuscles)
                    load.bodyweightMuscles.formUnion(exercise.secondaryMuscles)
                }
            }
        }
        return load
    }

    /// Region slug → 0…1 for `MuscleMapView`'s heat-map mode.
    static func slugIntensities(_ load: MuscleLoad) -> [String: Double] {
        guard let maxVolume = load.volume.values.max(), maxVolume > 0 else { return [:] }
        var result: [String: Double] = [:]
        for (muscle, volume) in load.volume {
            // Square root: legs outlift arms by an order of magnitude, and a linear scale
            // would leave the arms looking untrained.
            let intensity = (volume / maxVolume).squareRoot()
            for slug in MuscleAtlas.frontSlugs(for: [muscle]).union(MuscleAtlas.backSlugs(for: [muscle])) {
                // Muscles share regions (lats and middle back both draw as upper-back): the
                // heavier one wins — a sum would light the region brighter than any real load.
                result[slug] = max(result[slug] ?? 0, intensity)
            }
        }
        return result
    }

    /// Atlas muscles under `underloadThreshold` of the busiest one, minus those worked with
    /// bodyweight sets — their zero volume isn't neglect (decision 19).
    static func underloadedMuscles(_ load: MuscleLoad) -> [String] {
        let maxVolume = load.volume.values.max() ?? 0
        return MuscleAtlas.muscles.filter { muscle in
            guard !load.bodyweightMuscles.contains(muscle) else { return false }
            guard maxVolume > 0 else { return true }
            return (load.volume[muscle] ?? 0) / maxVolume < underloadThreshold
        }
    }

    /// Weight records set in `interval`, newest first.
    static func recentRecords(_ exercises: [AnalyticsExercise], in interval: DateInterval, limit: Int = 10) -> [AnalyticsRecord] {
        let records = exercises.flatMap { exercise -> [AnalyticsRecord] in
            let recordIDs = ExerciseStats.recordSetIDs(exercise.samples)
            return exercise.samples
                .filter { !$0.inProgress && recordIDs.contains($0.id) && isInside($0.date, interval) }
                .map { AnalyticsRecord(id: $0.id, exerciseID: exercise.id, exerciseName: exercise.name, weight: $0.weight, date: $0.date) }
        }
        return Array(records.sorted { $0.date > $1.date }.prefix(limit))
    }

    /// Every exercise with finished history, most recently done first.
    static func exerciseTrends(_ exercises: [AnalyticsExercise], calendar: Calendar) -> [ExerciseTrend] {
        exercises.compactMap { exercise -> ExerciseTrend? in
            let finished = exercise.samples.filter { !$0.inProgress }
            let sessions = ExerciseStats.sessions(finished)
            guard let last = sessions.first else { return nil }
            // Weight, not 1ПМ: the list agrees with records and the chart default (decisions 2, 17).
            let metric = ExerciseStats.availableMetrics(finished)[0]
            let value = metric.value(of: last)

            var direction: ExerciseTrend.Direction?
            if let value,
               let monthAgo = calendar.date(byAdding: .month, value: -1, to: last.date),
               let reference = sessions.first(where: { $0.date <= monthAgo }),
               let previous = metric.value(of: reference) {
                direction = value > previous ? .up : (value < previous ? .down : .flat)
            }
            return ExerciseTrend(
                exerciseID: exercise.id,
                name: exercise.name,
                lastDate: last.date,
                metric: metric,
                value: value,
                direction: direction
            )
        }
        .sorted { $0.lastDate > $1.lastDate }
    }
}
