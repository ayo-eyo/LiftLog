import SwiftUI
import SwiftData

struct WorkoutListView: View {
    let restTimer: RestTimer
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            List {
                ForEach(workouts) { workout in
                    NavigationLink {
                        WorkoutSummaryView(workout: workout, restTimer: restTimer)
                    } label: {
                        WorkoutRow(workout: workout)
                    }
                    .listRowBackground(Color.chalk)
                    .listRowSeparatorTint(.hairline)
                }
                .onDelete(perform: delete)
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

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(workouts[index])
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
                Text("Идёт").font(.mono(12)).foregroundStyle(.plateGreen)
            }
        }
    }
}
