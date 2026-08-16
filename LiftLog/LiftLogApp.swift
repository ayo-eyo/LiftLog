import SwiftUI
import SwiftData

@main
struct LiftLogApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView().preferredColorScheme(.light)
        }
        .modelContainer(Self.container)
    }

    /// The full model graph, listed explicitly rather than inferred from
    /// `Exercise`, so tests and the app agree on one schema.
    static let schema = Schema([
        Exercise.self,
        Workout.self,
        WorkoutSet.self,
        WorkoutItem.self,
    ])

    private static let container: ModelContainer = {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Не удалось создать ModelContainer: \(error)")
        }
    }()

    /// UI tests launch with `-uiTestInMemoryStore` (see `AppLauncher`) so each
    /// run starts from an empty store instead of resuming whatever workout the
    /// previous run left active. DEBUG-only: never reachable in a shipped build.
    private static var isUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uiTestInMemoryStore")
        #else
        false
        #endif
    }
}
