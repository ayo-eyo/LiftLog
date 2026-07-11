import SwiftUI
import SwiftData

@main
struct LiftLogApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Exercise.self)
    }
}
