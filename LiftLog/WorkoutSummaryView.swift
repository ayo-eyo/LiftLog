import SwiftUI
import SwiftData

struct WorkoutSummaryView: View {
    let workout: Workout
    let restTimer: RestTimer
    @State private var showingActive = false

    var body: some View {
        List {
            if workout.isActive {
                continueSection
            }
            ForEach(workout.exercises) { exercise in
                exerciseSection(exercise)
            }
        }
        .scrollContentBackground(.hidden)
        .background(.chalk)
        .navigationTitle(workout.date.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingActive) {
            ActiveWorkoutView(workout: workout, restTimer: restTimer)
        }
    }

    private var continueSection: some View {
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

    private func exerciseSection(_ exercise: Exercise) -> some View {
        Section {
            ForEach(workout.setsFor(exercise)) { set in
                setRow(set)
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

    private func setRow(_ set: WorkoutSet) -> some View {
        SetRow(weight: set.weight, reps: set.reps, fontSize: 14)
    }
}
