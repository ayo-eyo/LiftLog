import SwiftUI
import SwiftData

struct WorkoutListView: View {
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]

    var body: some View {
        NavigationStack {
            List(workouts) { workout in
                NavigationLink {
                    WorkoutSummaryView(workout: workout)
                } label: {
                    WorkoutRow(workout: workout)
                }
                .listRowBackground(Color.chalk)
                .listRowSeparatorTint(.hairline)
            }
            .scrollContentBackground(.hidden)
            .background(.chalk)
            .navigationTitle("Тренировки")
            .overlay {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "Тренировок пока нет",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("Нажми «Начать тренировку» внизу экрана")
                    )
                }
            }
        }
    }
}

private struct WorkoutRow: View {
    let workout: Workout

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.sans(16))
                    .foregroundStyle(.ink)
                Text("\(workout.exercises.count) упражнений · \(workout.sets.count) подходов")
                    .font(.mono(13))
                    .foregroundStyle(.steel)
            }
            Spacer()
            if workout.isActive {
                Text("Идёт")
                    .font(.mono(12))
                    .foregroundStyle(.plateGreen)
            }
        }
    }
}
