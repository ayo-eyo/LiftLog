import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    let workout: Workout
    let restTimer: RestTimer
    @Environment(\.dismiss) private var dismiss
    @State private var showingPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List(workout.exercises) { exercise in
                    NavigationLink {
                        WorkoutExerciseLogView(workout: workout, exercise: exercise, restTimer: restTimer)
                    } label: {
                        HStack(spacing: 11) {
                            ExerciseThumbnail(primaryMuscles: exercise.primaryMuscles, secondaryMuscles: exercise.secondaryMuscles, size: 44, cornerRadius: 9)
                            Text(exercise.name)
                                .font(.sans(16))
                                .foregroundStyle(.ink)
                            Spacer()
                            Text("\(workout.setsFor(exercise).count)")
                                .font(.mono(14))
                                .foregroundStyle(.steel)
                        }
                    }
                    .listRowBackground(Color.chalk)
                    .listRowSeparatorTint(.hairline)
                }
                .scrollContentBackground(.hidden)
                .background(.chalk)

                Button("Добавить упражнение") {
                    showingPicker = true
                }
                .font(.sans(15))
                .buttonStyle(.borderedProminent)
                .tint(.plateBlue)
                .padding()
            }
            .background(.chalk)
            .navigationTitle("Тренировка")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Завершить") {
                        restTimer.skip()
                        workout.finish()
                        HealthKitManager.save(workout)
                        WatchSessionManager.shared.pushSnapshot(for: nil)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView(excluding: Set(workout.exercises.compactMap { $0.catalogID })) { exercise in
                    workout.addExercise(exercise)
                    showingPicker = false
                    WatchSessionManager.shared.pushSnapshot(for: workout)
                }
            }
        }
        .onAppear {
            WatchSessionManager.shared.pushSnapshot(for: workout)
        }
    }
}
