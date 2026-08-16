import Foundation
import Observation

@Observable
final class RestTimer {
    static let defaultDuration: TimeInterval = 120

    private(set) var endDate: Date?
    private(set) var exerciseName: String?

    /// Closures rather than a protocol: `NotificationManager` is a stateless static
    /// enum, so there's nothing to fake beyond "don't call the real one" — tests
    /// pass no-ops instead of touching `UNUserNotificationCenter`.
    private let scheduleNotification: (TimeInterval, String) -> Void
    private let cancelNotification: () -> Void

    init(
        scheduleNotification: @escaping (TimeInterval, String) -> Void = { NotificationManager.scheduleRestTimerEnd(after: $0, exerciseName: $1) },
        cancelNotification: @escaping () -> Void = { NotificationManager.cancelRestTimerNotification() }
    ) {
        self.scheduleNotification = scheduleNotification
        self.cancelNotification = cancelNotification
    }

    func start(duration: TimeInterval, exerciseName: String, now: Date = .now) {
        endDate = now.addingTimeInterval(duration)
        self.exerciseName = exerciseName
        scheduleNotification(duration, exerciseName)
    }

    func skip() {
        endDate = nil
        cancelNotification()
    }

    func remaining(at date: Date) -> TimeInterval {
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSince(date))
    }

    func isResting(at date: Date) -> Bool {
        remaining(at: date) > 0
    }
}

extension TimeInterval {
    var clockString: String {
        let seconds = max(0, Int(self.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
