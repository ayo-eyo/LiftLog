import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    @Bindable var workout: Workout
    @Environment(\.dismiss) private var dismiss
    @State private var showingPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    ForEach(workout.exercises) { exercise in
                        Section(exercise.name) {
                            WorkoutExerciseRow(workout: workout, exercise: exercise)
                        }
                    }
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
                        workout.finish()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView(workout: workout)
            }
        }
    }
}

private struct WorkoutExerciseRow: View {
    @Bindable var workout: Workout
    let exercise: Exercise
    @Environment(\.modelContext) private var context

    @State private var weight: Double
    @State private var reps: Int

    init(workout: Workout, exercise: Exercise) {
        self.workout = workout
        self.exercise = exercise
        let last = exercise.sets.sorted { $0.createdAt < $1.createdAt }.last
        _weight = State(initialValue: last?.weight ?? 20)
        _reps = State(initialValue: last?.reps ?? 10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("кг", value: $weight, format: .number)
                    .font(.mono(16))
                    .keyboardType(.decimalPad)
                    .frame(width: 64)
                Text("×").foregroundStyle(.steel)
                TextField("повт.", value: $reps, format: .number)
                    .font(.mono(16))
                    .keyboardType(.numberPad)
                    .frame(width: 50)
                Spacer()
                Button {
                    workout.logSet(weight: weight, reps: reps, for: exercise, context: context)
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .tint(.plateBlue)
            }
            ForEach(workout.setsFor(exercise)) { set in
                HStack {
                    Text(set.weight.formatted(.number) + " кг").font(.mono(14))
                    Spacer()
                    Text("× \(set.reps)").font(.mono(14)).foregroundStyle(.steel)
                }
            }
        }
        .listRowBackground(Color.chalk)
    }
}
