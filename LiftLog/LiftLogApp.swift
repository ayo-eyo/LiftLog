import SwiftUI
import SwiftData

@main
struct LiftLogApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView().preferredColorScheme(.light)
        }
        .modelContainer(for: Exercise.self)
    }
}
