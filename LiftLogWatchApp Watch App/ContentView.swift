import SwiftUI

struct ContentView: View {
    private let phone = PhoneSessionManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        WatchWorkoutListView(phone: phone)
            .task {
                // Activate WCSession first: the notification permission prompt is
                // modal, and until the user answers it, phone.start() (and the snapshot
                // it would receive) hasn't happened, so the screen wrongly shows
                // "no active workout" the whole time the prompt is up.
                phone.start()
                await RestNotificationManager.requestAuthorization()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    // Coming back is the moment the phone is most likely reachable again
                    // — drain the queue, and ask for whatever changed on the phone while
                    // this app was away.
                    phone.flush()
                    phone.requestContext()
                default:
                    // The queue only drains while this app runs, so anything still in it
                    // is handed to the system on the way out.
                    phone.handOffToSystemDelivery()
                }
            }
    }
}
