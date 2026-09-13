import Foundation
import SwiftData

/// Epley one-rep-max estimate. A chart metric only, never a record — records are by
/// weight (plans/features/progress-analytics, decisions 2–3).
enum OneRepMax {
    /// Beyond this many reps the estimate stops meaning anything.
    static let maxReps = 12

    static func estimate(weight: Double, reps: Int) -> Double? {
        guard weight > 0, reps > 0, reps <= maxReps else { return nil }
        return reps == 1 ? weight : weight * (1 + Double(reps) / 30)
    }
}

/// One logged set, flattened out of SwiftData once so the statistics below are plain
/// value code: no relationship arrays walked inside loops, and nothing here needs a
/// `ModelContext` beyond building the samples.
struct SetSample: Hashable {
    enum SessionKey: Hashable {
        case workout(PersistentIdentifier)
        /// A set logged outside any workout, grouped by calendar day (decision 7). The app
        /// no longer creates these, but existing stores still hold them.
        case day(Date)
    }

    let id: PersistentIdentifier
    let weight: Double
    let reps: Int
    let date: Date
    let order: Int
    let sessionKey: SessionKey
    /// The workout's name; nil for a set logged outside any workout.
    let workoutName: String?
}

struct WeightRecordInfo: Equatable {
    let setID: PersistentIdentifier
    let weight: Double
    let reps: Int
    let date: Date
}

/// A just-logged set that beat the exercise's weight record — the banner's content.
struct WeightRecordBreak: Equatable {
    let setID: PersistentIdentifier
    let weight: Double
    /// The record it beat.
    let previous: Double
}

/// One exercise's weight record set in a given workout — a row of the completed summary.
struct WorkoutRecord {
    let exercise: Exercise
    /// The heaviest record set of the exercise in that workout.
    let weight: Double
}

/// One workout's worth of an exercise's sets (or one day's, outside a workout).
struct ExerciseSession: Identifiable, Equatable {
    let key: SetSample.SessionKey
    let workoutName: String?
    /// Chronological. Never empty — a session only exists because a set does.
    let sets: [SetSample]
    /// Whether any of `sets` set a weight record.
    let hasRecord: Bool

    var id: SetSample.SessionKey { key }
    var date: Date { sets.first?.date ?? .distantPast }
    var isStandalone: Bool {
        if case .day = key { return true }
        return false
    }
    var volume: Double { sets.reduce(0) { $0 + $1.weight * Double($1.reps) } }
    var maxWeight: Double? { sets.map(\.weight).filter { $0 > 0 }.max() }
    var bestOneRepMax: Double? { sets.compactMap { OneRepMax.estimate(weight: $0.weight, reps: $0.reps) }.max() }
    var maxReps: Int { sets.map(\.reps).max() ?? 0 }
}

enum ExerciseProgressMetric: String, CaseIterable, Identifiable {
    case weight, oneRepMax, volume, reps

    var id: Self { self }

    var title: String {
        switch self {
        case .weight: "Вес"
        case .oneRepMax: "1ПМ"
        case .volume: "Объём"
        case .reps: "Повторы"
        }
    }

    /// nil when the session has nothing to plot for this metric (e.g. a bodyweight
    /// session on the weight chart) — the point is skipped rather than drawn at zero.
    func value(of session: ExerciseSession) -> Double? {
        switch self {
        case .weight: session.maxWeight
        case .oneRepMax: session.bestOneRepMax
        case .volume: session.volume > 0 ? session.volume : nil
        case .reps: session.maxReps > 0 ? Double(session.maxReps) : nil
        }
    }
}

enum ExerciseChartPeriod: String, CaseIterable, Identifiable {
    case threeMonths, sixMonths, year, all

    var id: Self { self }

    var title: String {
        switch self {
        case .threeMonths: "3 мес"
        case .sixMonths: "6 мес"
        case .year: "Год"
        case .all: "Всё"
        }
    }

    /// Earliest date inside the period; nil for «Всё».
    func start(before now: Date, calendar: Calendar) -> Date? {
        switch self {
        case .threeMonths: calendar.date(byAdding: .month, value: -3, to: now)
        case .sixMonths: calendar.date(byAdding: .month, value: -6, to: now)
        case .year: calendar.date(byAdding: .year, value: -1, to: now)
        case .all: nil
        }
    }
}

struct ExerciseChartPoint: Identifiable, Equatable {
    let key: SetSample.SessionKey
    let date: Date
    let value: Double
    let hasRecord: Bool

    var id: SetSample.SessionKey { key }
}

/// Everything the progress screen shows, derived from an exercise's logged sets — nothing
/// here is stored, so editing or deleting a set re-derives records on the next read
/// (decision 1).
enum ExerciseStats {
    /// The exercise's whole history, chronological by `(createdAt, order)` — the sort key
    /// used everywhere else for sets. `order` only breaks ties within one workout (it's
    /// assigned per workout), which is exactly where equal timestamps happen: a batch of
    /// watch commands applied at once.
    static func samples(for exercise: Exercise, calendar: Calendar = .current) -> [SetSample] {
        exercise.sets
            // A plan can't have sets; the status check is defensive, the deletion check
            // isn't — a deleted but unsaved set still sits in an already-loaded array.
            .filter { !$0.isDeleted && $0.workout?.status != .plan }
            .map { set in
                let key: SetSample.SessionKey = set.workout.map { .workout($0.persistentModelID) }
                    ?? .day(calendar.startOfDay(for: set.createdAt))
                return SetSample(
                    id: set.persistentModelID,
                    weight: set.weight,
                    reps: set.reps,
                    date: set.createdAt,
                    order: set.order,
                    sessionKey: key,
                    workoutName: set.workout?.name
                )
            }
            .sorted { ($0.date, $0.order) < ($1.date, $1.order) }
    }

    /// Sets that were a weight record when logged. One pass with a running maximum —
    /// this runs on every render of the history.
    static func recordSetIDs(_ samples: [SetSample]) -> Set<PersistentIdentifier> {
        var best: Double?
        var records = Set<PersistentIdentifier>()
        for sample in samples {
            if WeightRecord.isRecord(weight: sample.weight, best: best) {
                records.insert(sample.id)
            }
            best = WeightRecord.raising(best, with: sample.weight)
        }
        return records
    }

    /// The heaviest set, the earliest one on a tie; nil when nothing was lifted with weight.
    static func currentRecord(_ samples: [SetSample]) -> WeightRecordInfo? {
        var heaviest: SetSample?
        for sample in samples where sample.weight > (heaviest?.weight ?? 0) {
            heaviest = sample
        }
        return heaviest.map { WeightRecordInfo(setID: $0.id, weight: $0.weight, reps: $0.reps, date: $0.date) }
    }

    /// Sessions newest first, each with its sets in order.
    static func sessions(_ samples: [SetSample]) -> [ExerciseSession] {
        let records = recordSetIDs(samples)
        var keys: [SetSample.SessionKey] = []
        var grouped: [SetSample.SessionKey: [SetSample]] = [:]
        for sample in samples {
            if grouped[sample.sessionKey] == nil {
                keys.append(sample.sessionKey)
            }
            grouped[sample.sessionKey, default: []].append(sample)
        }
        return keys.reversed().map { key in
            let sets = grouped[key] ?? []
            return ExerciseSession(
                key: key,
                workoutName: sets.first?.workoutName,
                sets: sets,
                hasRecord: sets.contains { records.contains($0.id) }
            )
        }
    }

    /// An exercise only ever done without weight has nothing but reps to chart.
    static func availableMetrics(_ samples: [SetSample]) -> [ExerciseProgressMetric] {
        samples.contains { $0.weight > 0 } ? [.weight, .oneRepMax, .volume] : [.reps]
    }

    /// Chart points, chronological: one per session inside `period` that has a value for
    /// `metric`.
    static func chartPoints(
        _ sessions: [ExerciseSession],
        metric: ExerciseProgressMetric,
        period: ExerciseChartPeriod,
        now: Date,
        calendar: Calendar
    ) -> [ExerciseChartPoint] {
        let start = period.start(before: now, calendar: calendar)
        return sessions.reversed().compactMap { session in
            if let start, session.date < start { return nil }
            guard let value = metric.value(of: session) else { return nil }
            return ExerciseChartPoint(key: session.key, date: session.date, value: value, hasRecord: session.hasRecord)
        }
    }

    /// Three months, unless fewer than two sessions fall inside them — then everything, so
    /// the screen doesn't open on an empty chart (FR-2).
    static func defaultPeriod(
        _ sessions: [ExerciseSession],
        metric: ExerciseProgressMetric,
        now: Date,
        calendar: Calendar
    ) -> ExerciseChartPeriod {
        let recent = chartPoints(sessions, metric: metric, period: .threeMonths, now: now, calendar: calendar)
        return recent.count >= 2 ? .threeMonths : .all
    }

    // MARK: During and after a workout (FR-3)

    /// «Прошлый раз»: the exercise's latest session that isn't `workout` itself and began
    /// before it did.
    static func lastSession(_ samples: [SetSample], before workout: Workout) -> ExerciseSession? {
        let key = SetSample.SessionKey.workout(workout.persistentModelID)
        let cutoff = workout.startedAt ?? workout.date
        return sessions(samples).first { $0.key != key && $0.date < cutoff }
    }

    /// The record `setID` broke, if it was one — same running maximum as `recordSetIDs`,
    /// stopping at that set so the banner can say what it beat.
    static func recordBeaten(by setID: PersistentIdentifier, in samples: [SetSample]) -> WeightRecordBreak? {
        var best: Double?
        for sample in samples {
            if sample.id == setID {
                guard let previous = best, WeightRecord.isRecord(weight: sample.weight, best: previous) else { return nil }
                return WeightRecordBreak(setID: setID, weight: sample.weight, previous: previous)
            }
            best = WeightRecord.raising(best, with: sample.weight)
        }
        return nil
    }

    /// Exercises of `workout` that set a weight record in it, each with its heaviest record
    /// set there. Marks come from each exercise's whole history — judged against this
    /// workout alone, every first set would be "a record".
    static func records(in workout: Workout) -> [WorkoutRecord] {
        let key = SetSample.SessionKey.workout(workout.persistentModelID)
        return workout.orderedExercises.compactMap { exercise in
            let exerciseSamples = samples(for: exercise)
            let recordIDs = recordSetIDs(exerciseSamples)
            let heaviest = exerciseSamples
                .filter { $0.sessionKey == key && recordIDs.contains($0.id) }
                .map(\.weight)
                .max()
            return heaviest.map { WorkoutRecord(exercise: exercise, weight: $0) }
        }
    }
}
