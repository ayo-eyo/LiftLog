import UserNotifications

enum NotificationManager {
    private static let restTimerID = "restTimer"

    static func requestAuthorization() async {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func scheduleRestTimerEnd(after duration: TimeInterval, exerciseName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Отдых окончен"
        content.body = "Пора продолжить: \(exerciseName)"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: duration, repeats: false)
        let request = UNNotificationRequest(identifier: restTimerID, content: content, trigger: trigger)

        Task {
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    static func cancelRestTimerNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [restTimerID])
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
