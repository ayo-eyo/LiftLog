import Foundation

/// The JSON backup: the whole history as plain `Codable` values, not the SwiftData models
/// (plans/features/backup-sync, FR-2). Entities point at each other by `syncID`, so a
/// file can be merged into a store that already holds part of it — and later serve as the
/// copy taken before iCloud sync is turned on.
///
/// `nonisolated` because encoding a large history runs off the main actor.
nonisolated struct BackupFile: Codable, Equatable, Sendable {
    /// Bump when a change can't be read by an older build; `BackupImporter.decode` refuses
    /// files newer than this instead of half-reading them.
    static let currentVersion = 1

    var formatVersion: Int
    var exportedAt: Date
    var appVersion: String?
    var exercises: [BackupExercise]
    var workouts: [BackupWorkout]
    /// Sets logged outside any workout. The app no longer creates them, but older stores
    /// hold them and they're part of the history.
    var standaloneSets: [BackupSet]
}

nonisolated struct BackupExercise: Codable, Equatable, Sendable {
    var syncID: UUID
    var name: String
    var catalogID: String?
    var createdAt: Date
}

nonisolated struct BackupWorkout: Codable, Equatable, Sendable {
    var syncID: UUID
    var name: String
    var date: Date
    var startedAt: Date?
    var completedAt: Date?
    var sortIndex: Int
    var version: Int
    var healthRecordedOnWatch: Bool
    /// Planned positions, by `order`.
    var items: [BackupItem]
    /// Logged sets, by `(createdAt, order)`.
    var sets: [BackupSet]
}

nonisolated struct BackupItem: Codable, Equatable, Sendable {
    var exerciseID: UUID?
    var order: Int
    var plannedWeight: Double?
    var plannedReps: Int?
}

nonisolated struct BackupSet: Codable, Equatable, Sendable {
    var exerciseID: UUID?
    var weight: Double
    var reps: Int
    var createdAt: Date
    var order: Int
}

/// Just enough of a file to check its version before decoding the rest.
nonisolated struct BackupHeader: Decodable {
    var formatVersion: Int
}

nonisolated enum BackupError: Error, Equatable, LocalizedError {
    case unreadable
    case newerFormat(Int)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "Это не файл резервной копии LiftLog, или он повреждён."
        case .newerFormat:
            "Файл создан более новой версией приложения. Обновите LiftLog и попробуйте снова."
        }
    }
}

/// One JSON encoder/decoder pair for backups. Dates are ISO 8601 with milliseconds: the
/// file stays readable by eye, and sets logged within the same second keep their order
/// when loaded back.
nonisolated enum BackupCoding {
    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(dateStyle))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(string, strategy: dateStyle) { return date }
            // A hand-edited file may drop the milliseconds.
            if let date = try? Date(string, strategy: Date.ISO8601FormatStyle()) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Не дата ISO 8601: \(string)"))
        }
        return decoder
    }
}
