import SwiftUI
import SwiftData

struct WorkoutSummaryView: View {
    @Bindable var workout: Workout
    @State private var showingActive = false

    var body: some View {
        List {
            if workout.isActive {
                Section {
                    Button("Продолжить тренировку") {
                        showingActive = true
                    }
                    .font(.sans(15))
                    .buttonStyle(.borderedProminent)
                    .tint(.plateBlue)
                }
                .listRowBackground(Color.chalk)
            }

            ForEach(workout.exercises) { exercise in
                Section {
                    ForEach(workout.setsFor(exercise)) { set in
                        HStack {
                            Text(set.weight.formatted(.number) + " кг")
                                .font(.mono(14)).foregroundStyle(.ink)
                            Spacer()
                            Text("× \(set.reps)")
                                .font(.mono(14)).foregroundStyle(.steel)
                        }
                    }
                    NavigationLink("Вся история упражнения") {
                        ExerciseDetailView(exercise: exercise)
                    }
                    .font(.sans(14))
                    .foregroundStyle(.plateBlue)
                } header: {
                    Text(exercise.name).font(.sans(15)).foregroundStyle(.ink)
                }
                .listRowBackground(Color.chalk)
            }
        }
        .scrollContentBackground(.hidden)
        .background(.chalk)
        .navigationTitle(workout.date.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingActive) {
            ActiveWorkoutView(workout: workout)
        }
    }
}
