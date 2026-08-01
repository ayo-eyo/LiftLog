import Foundation
import Observation

@Observable
final class RestTimer {
    private(set) var endDate: Date?
    private(set) var exerciseName: String?

    func start(duration: TimeInterval, exerciseName: String) {
        endDate = Date().addingTimeInterval(duration)
        self.exerciseName = exerciseName
        NotificationManager.scheduleRestTimerEnd(after: duration, exerciseName: exerciseName)
    }

    func skip() {
        endDate = nil
        NotificationManager.cancelRestTimerNotification()
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
