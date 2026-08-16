import SwiftUI

struct ContentView: View {
    @ObservedObject private var phone = PhoneSessionManager.shared

    var body: some View {
        WorkoutSetsView(phone: phone)
            .task {
                await RestNotificationManager.requestAuthorization()
                phone.start()
            }
    }
}
