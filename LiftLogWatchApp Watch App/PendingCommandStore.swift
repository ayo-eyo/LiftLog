import Foundation
import os

/// On-disk home of the offline queue.
///
/// The whole point of queueing instead of handing everything to `transferUserInfo` is
/// that the watch stays in charge of what has and hasn't reached the phone — which only
/// works if the queue survives watchOS suspending or killing the app between sets.
@MainActor
final class PendingCommandStore {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LiftLogWatchApp", category: "PendingQueue")
    private let url: URL

    init(filename: String = "pending-commands.json") {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appending(path: filename)
    }

    func load() -> [WatchPendingCommand] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder().decode([WatchPendingCommand].self, from: data)
        } catch {
            // A queue we can't read is worse than no queue: it would keep failing on
            // every launch. Log it and start clean.
            logger.error("failed to decode pending queue, dropping it: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: url)
            return []
        }
    }

    func save(_ commands: [WatchPendingCommand]) {
        do {
            if commands.isEmpty {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                return
            }
            try JSONEncoder().encode(commands).write(to: url, options: .atomic)
        } catch {
            logger.error("failed to persist pending queue: \(error.localizedDescription)")
        }
    }
}
