import Foundation
import SwiftData
@testable import LiftLog

/// Builders for the model graph. All of them insert into the passed context so a
/// test never has to remember the insert/append pairing that `Workout.logSet`
/// and `Workout.addExercise` rely on.
///
/// Dates are deterministic: `Fixtures.epoch` plus an offset, never `.now`, so
/// ordering assertions (`setsFor`, `sortedItems`) are stable.
@MainActor
enum Fixtures {
    /// 2025-01-01 00:00:00 UTC.
    /// `nonisolated`, потому что используется как значение по умолчанию у параметров —
    /// они вычисляются вне главного актора.
    nonisolated static let epoch = Date(timeIntervalSince1970: 1_735_689_600)

    nonisolated static func date(offset seconds: TimeInterval) -> Date {
        epoch.addingTimeInterval(seconds)
    }

    // MARK: Exercises

    @discardableResult
    static func exercise(
        _ name: String = "Жим лёжа",
        catalogID: String? = nil,
        createdAt: Date = epoch,
        in context: ModelContext
    ) -> Exercise {
        let exercise = Exercise(name: name, catalogID: catalogID, createdAt: createdAt)
        context.insert(exercise)
        return exercise
    }

    /// An exercise linked to a real catalog entry, so `catalogExercise`,
    /// `primaryMuscles` and the muscle map resolve to real data.
    @discardableResult
    static func catalogBackedExercise(
        catalogID: String = "Barbell_Bench_Press_-_Medium_Grip",
        in context: ModelContext
    ) -> Exercise {
        let catalog = ExerciseCatalog.byID[catalogID]
        let exercise = Exercise(name: catalog?.name ?? catalogID, catalogID: catalogID, createdAt: epoch)
        context.insert(exercise)
        return exercise
    }

    // MARK: Workouts

    /// Builds a workout. `startedAt` defaults to `epoch` (i.e. active) since most
    /// tests care about an in-progress workout — pass `startedAt: nil` for a plan,
    /// or `completedAt:` for a finished one.
    @discardableResult
    static func workout(
        date: Date = epoch,
        name: String = "",
        startedAt: Date? = epoch,
        completedAt: Date? = nil,
        sortIndex: Int = 0,
        exercises: [Exercise] = [],
        items: [(exercise: Exercise, weight: Double?, reps: Int?)] = [],
        in context: ModelContext
    ) -> Workout {
        let workout = Workout(date: date, name: name, sortIndex: sortIndex)
        context.insert(workout)
        workout.startedAt = startedAt
        workout.completedAt = completedAt
        for exercise in exercises {
            workout.addExercise(exercise, context: context)
        }
        for item in items {
            workout.addExercise(item.exercise, weight: item.weight, reps: item.reps, context: context)
        }
        return workout
    }

    /// Logs `sets` in order via the production path (`Workout.logSet`), so the
    /// exercise/workout back-references are wired exactly as the app wires them.
    static func log(
        _ sets: [(weight: Double, reps: Int)],
        for exercise: Exercise,
        in workout: Workout,
        context: ModelContext
    ) {
        for set in sets {
            workout.logSet(weight: set.weight, reps: set.reps, for: exercise, context: context)
        }
    }

    /// `epoch` plus `days` whole days.
    nonisolated static func day(_ days: Int) -> Date {
        epoch.addingTimeInterval(Double(days) * 86_400)
    }

    /// Gregorian calendar pinned to UTC, so day and month boundaries in a test don't move
    /// with the machine's time zone.
    nonisolated static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// A finished workout holding `sets` of one exercise, built the way the app builds it —
    /// one planned position per set, `start`, `logSet` a minute apart, `finish` — so an
    /// exercise's history can be laid out across days deterministically.
    @discardableResult
    static func completedWorkout(
        _ exercise: Exercise,
        sets: [(weight: Double, reps: Int)],
        on date: Date = epoch,
        name: String = "",
        in context: ModelContext
    ) -> Workout {
        let workout = Workout(date: date, name: name)
        context.insert(workout)
        for _ in sets {
            workout.addExercise(exercise, context: context)
        }
        workout.start(now: date)
        for (index, set) in sets.enumerated() {
            workout.logSet(weight: set.weight, reps: set.reps, for: exercise, now: date.addingTimeInterval(Double(index + 1) * 60), context: context)
        }
        workout.finish(now: date.addingTimeInterval(Double(sets.count + 1) * 60))
        return workout
    }

    /// A set logged outside any workout. The app can no longer create one (the standalone
    /// input on `ExerciseDetailView` is gone, and `Exercise.addSet` with it), but existing
    /// stores still hold them — so history and cascade tests build them the way the
    /// removed `Exercise.addSet` did.
    @discardableResult
    static func standaloneSet(
        weight: Double,
        reps: Int,
        for exercise: Exercise,
        at date: Date = epoch,
        in context: ModelContext
    ) -> WorkoutSet {
        let order = (exercise.sets.map(\.order).max() ?? -1) + 1
        let set = WorkoutSet(weight: weight, reps: reps, createdAt: date, order: order)
        context.insert(set)
        exercise.sets.append(set)
        return set
    }

    // MARK: RestTimer

    /// A `RestTimer` whose notification hooks are no-ops, so tests never touch the
    /// real `UNUserNotificationCenter`.
    static func restTimer() -> RestTimer {
        RestTimer(scheduleNotification: { _, _ in }, cancelNotification: {})
    }
}
