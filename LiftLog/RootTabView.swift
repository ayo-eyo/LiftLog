import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Workout> { $0.completedAt == nil })
    private var activeWorkouts: [Workout]

    @State private var presentedWorkout: Workout?
    @State private var restTimer = RestTimer()

    var body: some View {
        TabView {
            Tab("Тренировки", systemImage: "figure.strengthtraining.traditional") {
                WorkoutListView(restTimer: restTimer)
            }
            Tab("Шаблоны", systemImage: "list.bullet.rectangle") {
                TemplateListView(restTimer: restTimer)
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
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Button {
                    startOrResumeWorkout()
                } label: {
                    Label(accessoryText(at: timeline.date), systemImage: "play.fill")
                }
            }
        }
        .fullScreenCover(item: $presentedWorkout) { workout in
            ActiveWorkoutView(workout: workout, restTimer: restTimer)
        }
        .task {
            await HealthKitManager.requestAuthorization()
            await NotificationManager.requestAuthorization()
        }
        .onAppear {
            DataIntegrity.deduplicateSyncIDs(context: context)
            WatchSessionManager.shared.start(modelContext: context, restTimer: restTimer)
        }
    }

    private func accessoryText(at date: Date) -> String {
        if restTimer.isResting(at: date), let name = restTimer.exerciseName {
            return "\(name) · \(restTimer.remaining(at: date).clockString)"
        }
        return activeWorkouts.isEmpty ? "Начать тренировку" : "Тренировка идёт"
    }

    private func startOrResumeWorkout() {
        if let existing = activeWorkouts.first {
            presentedWorkout = existing
        } else {
            let new = Workout()
            context.insert(new)
            presentedWorkout = new
        }
    }
}
