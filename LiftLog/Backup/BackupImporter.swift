import Foundation
import SwiftData

struct ImportPreview: Equatable {
    var newWorkouts = 0
    /// Already in the store by `syncID` — skipped whole.
    var existingWorkouts = 0
    var newExercises = 0
    var newStandaloneSets = 0
    /// A running workout from the file will be added as finished, because one is already
    /// running here (or earlier in the same file).
    var activeBecomesCompleted = false

    var hasChanges: Bool { newWorkouts > 0 || newExercises > 0 || newStandaloneSets > 0 }
}

struct ImportResult: Equatable {
    var addedWorkouts = 0
    var addedExercises = 0
    var addedStandaloneSets = 0
}

/// Merges a backup into the store (plans/features/backup-sync, FR-4): adds what's missing,
/// never overwrites what's there, and a second import of the same file adds nothing.
enum BackupImporter {
    nonisolated static func decode(_ data: Data) throws -> BackupFile {
        let decoder = BackupCoding.decoder()
        guard let header = try? decoder.decode(BackupHeader.self, from: data) else {
            throw BackupError.unreadable
        }
        guard header.formatVersion <= BackupFile.currentVersion else {
            throw BackupError.newerFormat(header.formatVersion)
        }
        do {
            return try decoder.decode(BackupFile.self, from: data)
        } catch {
            throw BackupError.unreadable
        }
    }

    /// What `apply` would do, without writing anything.
    static func preview(_ file: BackupFile, context: ModelContext) throws -> ImportPreview {
        let plan = try makePlan(file, context: context)
        let runningInFile = plan.newWorkouts.filter(isRunning).count
        return ImportPreview(
            newWorkouts: plan.newWorkouts.count,
            existingWorkouts: file.workouts.count - plan.newWorkouts.count,
            newExercises: plan.missingExercises.count,
            newStandaloneSets: plan.newStandaloneSets.count,
            activeBecomesCompleted: runningInFile > (plan.hasRunningWorkout ? 0 : 1)
        )
    }

    /// Applies the file and saves once. On a failed save the context is rolled back, so a
    /// half-applied import never lands — callers pass a context of their own
    /// (`autosaveEnabled = false`) so nothing partial shows in the UI in the meantime.
    @discardableResult
    static func apply(_ file: BackupFile, context: ModelContext) throws -> ImportResult {
        let plan = try makePlan(file, context: context)

        var created: [UUID: Exercise] = [:]
        for backup in plan.missingExercises {
            let exercise = Exercise(name: backup.name, catalogID: backup.catalogID, createdAt: backup.createdAt)
            exercise.syncID = backup.syncID
            context.insert(exercise)
            created[backup.syncID] = exercise
        }
        func exercise(for id: UUID?) -> Exercise? {
            guard let id else { return nil }
            return plan.matched[id] ?? created[plan.aliases[id] ?? id]
        }

        // FR-4 / open question 2: a running workout stays running only if nothing runs here —
        // the app allows one at a time — otherwise it's added as finished at its last set.
        var hasRunningWorkout = plan.hasRunningWorkout
        for backup in plan.newWorkouts {
            let workout = Workout(date: backup.date, name: backup.name, sortIndex: backup.sortIndex)
            workout.syncID = backup.syncID
            context.insert(workout)
            workout.startedAt = backup.startedAt
            workout.completedAt = backup.completedAt
            if isRunning(backup) {
                if hasRunningWorkout {
                    workout.completedAt = backup.sets.map(\.createdAt).max() ?? backup.startedAt
                } else {
                    hasRunningWorkout = true
                }
            }
            workout.version = backup.version
            workout.healthRecordedOnWatch = backup.healthRecordedOnWatch

            // Straight inserts with the file's own `order`/`createdAt` — not
            // `addExercise`/`logSet`, which renumber, stamp "now" and bump `version`.
            for backupItem in backup.items {
                let item = WorkoutItem(
                    exercise: exercise(for: backupItem.exerciseID),
                    plannedWeight: backupItem.plannedWeight,
                    plannedReps: backupItem.plannedReps,
                    order: backupItem.order
                )
                context.insert(item)
                workout.items.append(item)
            }
            for backupSet in backup.sets {
                let set = WorkoutSet(weight: backupSet.weight, reps: backupSet.reps, createdAt: backupSet.createdAt, order: backupSet.order)
                context.insert(set)
                workout.sets.append(set)
                exercise(for: backupSet.exerciseID)?.sets.append(set)
            }
        }

        for backupSet in plan.newStandaloneSets {
            guard let owner = exercise(for: backupSet.exerciseID) else { continue }
            let set = WorkoutSet(weight: backupSet.weight, reps: backupSet.reps, createdAt: backupSet.createdAt, order: backupSet.order)
            context.insert(set)
            owner.sets.append(set)
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return ImportResult(
            addedWorkouts: plan.newWorkouts.count,
            addedExercises: plan.missingExercises.count,
            addedStandaloneSets: plan.newStandaloneSets.count
        )
    }

    // MARK: Planning

    private struct Plan {
        /// File exercise `syncID` → the existing exercise it merges into.
        var matched: [UUID: Exercise] = [:]
        /// Exercises to create, one per distinct exercise.
        var missingExercises: [BackupExercise] = []
        /// File exercise `syncID` → the missing exercise it's a duplicate of (same
        /// `catalogID` or name), so the file's own duplicates aren't created twice.
        var aliases: [UUID: UUID] = [:]
        var newWorkouts: [BackupWorkout] = []
        var newStandaloneSets: [BackupSet] = []
        var hasRunningWorkout = false
    }

    private static func makePlan(_ file: BackupFile, context: ModelContext) throws -> Plan {
        let existingExercises = try context.fetch(FetchDescriptor<Exercise>()).filter { !$0.isDeleted }
        let existingWorkouts = try context.fetch(FetchDescriptor<Workout>()).filter { !$0.isDeleted }
        var plan = Plan()
        plan.hasRunningWorkout = existingWorkouts.contains { $0.isActive }

        // syncID first, then catalogID, then name — so the exercise's history stays one
        // history even when the file came from a different install.
        let bySyncID = Dictionary(existingExercises.map { ($0.syncID, $0) }, uniquingKeysWith: { first, _ in first })
        let byCatalogID = Dictionary(existingExercises.compactMap { exercise in exercise.catalogID.map { ($0, exercise) } }, uniquingKeysWith: { first, _ in first })
        let byName = Dictionary(existingExercises.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var missingByCatalogID: [String: UUID] = [:]
        var missingByName: [String: UUID] = [:]
        for backup in file.exercises {
            if let existing = bySyncID[backup.syncID] ?? backup.catalogID.flatMap({ byCatalogID[$0] }) ?? byName[backup.name] {
                plan.matched[backup.syncID] = existing
            } else if let representative = backup.catalogID.flatMap({ missingByCatalogID[$0] }) ?? missingByName[backup.name] {
                plan.aliases[backup.syncID] = representative
            } else {
                plan.missingExercises.append(backup)
                if let catalogID = backup.catalogID { missingByCatalogID[catalogID] = backup.syncID }
                missingByName[backup.name] = backup.syncID
            }
        }

        let existingWorkoutIDs = Set(existingWorkouts.map(\.syncID))
        plan.newWorkouts = file.workouts.filter { !existingWorkoutIDs.contains($0.syncID) }

        // Sets have no syncID; a standalone set counts as present when its exercise already
        // holds one with the same moment, weight and reps.
        let knownExerciseIDs = Set(file.exercises.map(\.syncID))
        let existingStandaloneKeys = Set(existingExercises.flatMap { exercise in
            exercise.sets
                .filter { $0.workout == nil && !$0.isDeleted }
                .map { standaloneKey(exerciseID: exercise.syncID, weight: $0.weight, reps: $0.reps, date: $0.createdAt) }
        })
        plan.newStandaloneSets = file.standaloneSets.filter { set in
            guard let id = set.exerciseID, knownExerciseIDs.contains(id) else { return false }
            guard let existing = plan.matched[id] else { return true }
            return !existingStandaloneKeys.contains(standaloneKey(exerciseID: existing.syncID, weight: set.weight, reps: set.reps, date: set.createdAt))
        }
        return plan
    }

    private static func isRunning(_ workout: BackupWorkout) -> Bool {
        workout.startedAt != nil && workout.completedAt == nil
    }

    /// Milliseconds, not the raw `Date`: the file keeps millisecond precision, the store more.
    private static func standaloneKey(exerciseID: UUID, weight: Double, reps: Int, date: Date) -> String {
        let milliseconds = Int((date.timeIntervalSinceReferenceDate * 1000).rounded())
        return "\(exerciseID.uuidString)|\(milliseconds)|\(weight)|\(reps)"
    }
}
