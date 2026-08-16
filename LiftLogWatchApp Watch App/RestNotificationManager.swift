import UserNotifications

/// Schedules the rest-timer-end alert directly on the watch, rather than relying
/// on iOS mirroring the phone's local notification — mirroring only happens when
/// the phone is locked/idle, so during a hands-on-watch workout it's unreliable.
enum RestNotificationManager {
    private static let restTimerID = "restTimer"

    static func requestAuthorization() async {
        try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func schedule(endDate: Date, exerciseName: String?) {
        cancel()
        let interval = endDate.timeIntervalSinceNow
        guard interval > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Отдых окончен"
        content.body = exerciseName.map { "Пора продолжить: \($0)" } ?? "Пора продолжить"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: restTimerID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [restTimerID])
    }
}
