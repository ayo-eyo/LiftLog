import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Workout> { $0.startedAt != nil && $0.completedAt == nil })
    private var activeWorkouts: [Workout]

    @State private var presentedWorkout: Workout?
    @State private var restTimer = RestTimer()
    @State private var didRunDataIntegrityCheck = false

    var body: some View {
        TabView {
            Tab("Тренировки", systemImage: "figure.strengthtraining.traditional") {
                WorkoutListView(restTimer: restTimer)
            }
            Tab("Упражнения", systemImage: "books.vertical") {
                CatalogView()
            }
            Tab("Аналитика", systemImage: "chart.xyaxis.line") {
                AnalyticsPlaceholderView()
            }
        }
        .tint(.plateBlue)
        // Only ever a resume affordance for the one workout that can be active at a
        // time — never a way to start a new one from an arbitrary screen. Starting
        // is explicit: the "+" in the workout list, or a plan's own «Начать».
        .startAccessory(isVisible: !activeWorkouts.isEmpty) {
            accessoryButton
        }
        .fullScreenCover(item: $presentedWorkout) { workout in
            NavigationStack {
                WorkoutDetailView(workout: workout, restTimer: restTimer)
            }
        }
        .task {
            await HealthKitManager.requestAuthorization()
            await NotificationManager.requestAuthorization()
        }
        .onAppear {
            if !didRunDataIntegrityCheck {
                didRunDataIntegrityCheck = true
                DataIntegrity.deduplicateSyncIDs(context: context)
                DataIntegrity.restoreWorkoutComposition(context: context)
            }
            WatchSessionManager.shared.start(modelContext: context, restTimer: restTimer)
        }
    }

    /// `TimelineView(.periodic)` only exists while resting — gated on `restTimer.endDate`
    /// instead of running for the whole time the accessory is on screen (i.e. whenever a
    /// workout is active).
    @ViewBuilder
    private var accessoryButton: some View {
        if let endDate = restTimer.endDate {
            TimelineView(.periodic(from: endDate, by: 1)) { timeline in
                startButton(at: timeline.date)
            }
        } else {
            startButton(at: .now)
        }
    }

    private func startButton(at date: Date) -> some View {
        Button {
            presentedWorkout = activeWorkouts.first
        } label: {
            Label(Self.accessoryText(restTimer: restTimer, at: date), systemImage: "play.fill")
        }
        .accessibilityIdentifier("root.startAccessory")
    }

    /// Pulled out of `startButton(at:)` so it's testable without a live `@Query` /
    /// view hierarchy — takes plain values instead of reading `self`. Only ever shown
    /// while a workout is active (see `startAccessory(isVisible:)` above), so there's
    /// no "nothing active" case to render text for.
    static func accessoryText(restTimer: RestTimer, at date: Date) -> String {
        if restTimer.isResting(at: date), let name = restTimer.exerciseName {
            return "\(name) · \(restTimer.remaining(at: date).clockString)"
        }
        return "Тренировка идёт"
    }
}

private extension View {
    /// `tabViewBottomAccessory { if isVisible { content() } }` leaves an empty glass
    /// pill on screen when `isVisible` is false — collapsing the *content* to nothing
    /// doesn't collapse the accessory bar's own background (radar-worthy on iOS 26.0).
    /// iOS 26.1 added an `isEnabled` overload that removes the bar itself; fall back to
    /// the old (visually broken) pattern below that OS version since there's no other
    /// way to fully hide it pre-26.1.
    @ViewBuilder
    func startAccessory<Content: View>(isVisible: Bool, @ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 26.1, *) {
            tabViewBottomAccessory(isEnabled: isVisible) { content() }
        } else {
            tabViewBottomAccessory {
                if isVisible {
                    content()
                }
            }
        }
    }
}
