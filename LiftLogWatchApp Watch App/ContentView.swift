import SwiftUI

struct ContentView: View {
    private let phone = PhoneSessionManager.shared

    var body: some View {
        WorkoutSetsView(phone: phone)
            .task {
                // Activate WCSession first: the notification permission prompt is
                // modal, and until the user answers it, phone.start() (and the snapshot
                // it would receive) hasn't happened, so the screen wrongly shows
                // "no active workout" the whole time the prompt is up.
                phone.start()
                await RestNotificationManager.requestAuthorization()
            }
    }
}
