import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Workout> { $0.completedAt == nil })
    private var activeWorkouts: [Workout]
    
    @State private var presentedWorkout: Workout?
    
    var body: some View {
        TabView {
            Tab("Тренировки", systemImage: "figure.strengthtraining.traditional") {
                ContentView()
            }
            Tab("Шаблоны", systemImage: "list.bullet.rectangle") {
                TemplatesPlaceholderView()
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
            Button {
                startOrResumeWorkout()
            } label: {
                Label(
                activeWorkouts.isEmpty ? "Начать тренировку" : "Тренировка идёт",
                systemImage: "play.fill"
                )
            }
        }
        .fullScreenCover(item: $presentedWorkout) { workout in
            ActiveWorkoutView(workout: workout)
        }
    }
    
    private func startOrResumeWorkout() {
        if let workout = activeWorkouts.first {
            presentedWorkout = workout
        } else {
            let new = Workout()
            context.insert(new)
            presentedWorkout = new
        }
    }
}
