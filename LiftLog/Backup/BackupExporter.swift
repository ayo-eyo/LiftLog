import Foundation
import SwiftData

/// Builds backups from the store. Snapshotting into `BackupFile` needs the models and runs
/// on the main actor; everything after that — encoding, CSV, writing the file — works on
/// the plain values and can run anywhere.
enum BackupExporter {
    nonisolated enum Kind {
        case json, csv
    }

    /// The whole history. Sorted deterministically (ties broken by `syncID`), so two
    /// exports of the same data are identical — the round-trip tests compare files.
    static func makeFile(context: ModelContext, now: Date = .now) throws -> BackupFile {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
            .filter { !$0.isDeleted }
            .sorted { ($0.createdAt, $0.syncID.uuidString) < ($1.createdAt, $1.syncID.uuidString) }
        // A row deleted but not yet saved still comes back from a fetch.
        let workouts = try context.fetch(FetchDescriptor<Workout>())
            .filter { !$0.isDeleted }
            .sorted { ($0.date, $0.syncID.uuidString) < ($1.date, $1.syncID.uuidString) }
        let standaloneSets = exercises
            .flatMap { exercise in exercise.sets.filter { $0.workout == nil && !$0.isDeleted } }
            .sorted(by: isInSetOrder)

        return BackupFile(
            formatVersion: BackupFile.currentVersion,
            exportedAt: now,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            exercises: exercises.map {
                BackupExercise(syncID: $0.syncID, name: $0.name, catalogID: $0.catalogID, createdAt: $0.createdAt)
            },
            workouts: workouts.map(backup(of:)),
            standaloneSets: standaloneSets.map(backup(of:))
        )
    }

    private static func backup(of workout: Workout) -> BackupWorkout {
        BackupWorkout(
            syncID: workout.syncID,
            name: workout.name,
            date: workout.date,
            startedAt: workout.startedAt,
            completedAt: workout.completedAt,
            sortIndex: workout.sortIndex,
            version: workout.version,
            healthRecordedOnWatch: workout.healthRecordedOnWatch,
            items: workout.items
                .filter { !$0.isDeleted }
                .sorted { $0.order < $1.order }
                .map { BackupItem(exerciseID: $0.exercise?.syncID, order: $0.order, plannedWeight: $0.plannedWeight, plannedReps: $0.plannedReps) },
            sets: workout.sets
                .filter { !$0.isDeleted }
                .sorted(by: isInSetOrder)
                .map(backup(of:))
        )
    }

    private static func backup(of set: WorkoutSet) -> BackupSet {
        BackupSet(exerciseID: set.exercise?.syncID, weight: set.weight, reps: set.reps, createdAt: set.createdAt, order: set.order)
    }

    /// Same `(createdAt, order)` key the rest of the app sorts sets by.
    private static func isInSetOrder(_ lhs: WorkoutSet, _ rhs: WorkoutSet) -> Bool {
        (lhs.createdAt, lhs.order) < (rhs.createdAt, rhs.order)
    }

    // MARK: Off the main actor

    nonisolated static func encodeJSON(_ file: BackupFile) throws -> Data {
        try BackupCoding.encoder().encode(file)
    }

    /// `LiftLog-2026-09-13.json`, `LiftLog-sets-2026-09-13.csv` — the local date.
    nonisolated static func fileName(_ kind: Kind, date: Date, timeZone: TimeZone = .current) -> String {
        let day = date.formatted(Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day())
        switch kind {
        case .json: return "LiftLog-\(day).json"
        case .csv: return "LiftLog-sets-\(day).csv"
        }
    }

    /// Writes into the temporary directory, replacing an earlier export of the same name.
    nonisolated static func writeTemporaryFile(_ data: Data, named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// One row per set (FR-3). `;` as separator, decimal comma and a UTF-8 BOM, so the file
    /// opens with a double click in Russian-locale Excel as well as in Numbers; CRLF line
    /// ends for Excel.
    nonisolated static func csv(from file: BackupFile, timeZone: TimeZone = .current) -> String {
        let exerciseNames = Dictionary(file.exercises.map { ($0.syncID, $0.name) }, uniquingKeysWith: { first, _ in first })
        let russian = Locale(identifier: "ru_RU")
        let dayFormatter = DateFormatter()
        dayFormatter.locale = russian
        dayFormatter.timeZone = timeZone
        dayFormatter.dateFormat = "dd.MM.yyyy"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = russian
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = "HH:mm"

        var lines = ["Дата;Время;Тренировка;Упражнение;Подход;Вес, кг;Повторы"]
        func appendRows(_ sets: [BackupSet], workoutName: String) {
            var setNumbers: [UUID?: Int] = [:]
            for set in sets {
                let number = (setNumbers[set.exerciseID] ?? 0) + 1
                setNumbers[set.exerciseID] = number
                let fields = [
                    dayFormatter.string(from: set.createdAt),
                    timeFormatter.string(from: set.createdAt),
                    workoutName,
                    set.exerciseID.flatMap { exerciseNames[$0] } ?? "",
                    String(number),
                    set.weight.formatted(.number.locale(russian).grouping(.never)),
                    String(set.reps),
                ]
                lines.append(fields.map(csvField).joined(separator: ";"))
            }
        }
        for workout in file.workouts {
            appendRows(workout.sets, workoutName: workout.name.isEmpty ? "Тренировка" : workout.name)
        }
        appendRows(file.standaloneSets, workoutName: "Вне тренировки")
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Quotes a field that holds the separator, a quote or a line break; quotes inside are
    /// doubled.
    nonisolated static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == ";" || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
