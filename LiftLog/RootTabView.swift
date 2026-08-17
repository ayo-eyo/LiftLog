import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Workout> { $0.startedAt != nil && $0.completedAt == nil })
    private var activeWorkouts: [Workout]

    @State private var presentedWorkout: Workout?
    @State private var restTimer = RestTimer()
    @State private var didRunDataIntegrityCheck = false
    @State private var hidesStartAccessory = false

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
        .tabViewBottomAccessory {
            if !hidesStartAccessory {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Button {
                        startOrResumeWorkout()
                    } label: {
                        Label(accessoryText(at: timeline.date), systemImage: "play.fill")
                    }
                    .accessibilityIdentifier("root.startAccessory")
                }
            }
        }
        .onPreferenceChange(HidesStartAccessoryPreferenceKey.self) { hidesStartAccessory = $0 }
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

    private func accessoryText(at date: Date) -> String {
        Self.accessoryText(restTimer: restTimer, hasActiveWorkout: !activeWorkouts.isEmpty, at: date)
    }

    private func startOrResumeWorkout() {
        presentedWorkout = Self.workoutToResume(activeWorkouts: activeWorkouts, context: context)
    }

    /// Pulled out of `accessoryText(at:)` so it's testable without a live `@Query` /
    /// view hierarchy — takes plain values instead of reading `self`.
    static func accessoryText(restTimer: RestTimer, hasActiveWorkout: Bool, at date: Date) -> String {
        if restTimer.isResting(at: date), let name = restTimer.exerciseName {
            return "\(name) · \(restTimer.remaining(at: date).clockString)"
        }
        return hasActiveWorkout ? "Тренировка идёт" : "Начать тренировку"
    }

    /// Pulled out of `startOrResumeWorkout()` so the "resume existing vs. create new"
    /// decision is testable without a live `@Query` / view hierarchy. Never picks up
    /// a plan — a plan is only started explicitly from its own screen, since picking
    /// one implicitly here would be ambiguous about which plan to start.
    static func workoutToResume(activeWorkouts: [Workout], context: ModelContext) -> Workout {
        if let existing = activeWorkouts.first {
            return existing
        }
        let new = Workout()
        context.insert(new)
        new.start()
        return new
    }
}
