import SwiftUI
import SwiftData

/// Activates `WCSession` at process launch rather than waiting for `RootTabView` to
/// appear. iOS can wake the app in the background purely to deliver a WatchConnectivity
/// message (e.g. a `.finish` from the watch) with no scene ever created — without this,
/// the session delegate is never assigned and the message is dropped or left queued
/// until the user happens to open the app. See technical-notes.md §5.4.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        WatchSessionManager.shared.start(modelContext: LiftLogApp.container.mainContext)
        return true
    }
}

@main
struct LiftLogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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

    // `fileprivate`, not `private`: `AppDelegate` above needs it too, and Swift's
    // `private` doesn't cross type boundaries even within the same file.
    fileprivate static let container: ModelContainer = {
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
    static var isUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uiTestInMemoryStore")
        #else
        false
        #endif
    }
}
