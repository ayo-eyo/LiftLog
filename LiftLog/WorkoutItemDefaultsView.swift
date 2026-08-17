import SwiftUI
import SwiftData

/// Add/edit planned weight×reps positions for one exercise in a workout that
/// isn't active yet — the plan-building successor to `TemplateItemDefaultsView`.
struct WorkoutItemDefaultsView: View {
    let workout: Workout
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var weight: Double
    @State private var reps: Int
    /// Tapping a planned row switches `inputBlock` from "add a new position" into
    /// "edit this one" — reusing the same fields rather than opening a second
    /// screen. A separate edit sheet presented over this (already pushed) view
    /// caused every keystroke to bounce observers on `workout.items` all the way
    /// up through `WorkoutDetailView`, which reliably dropped keyboard focus after
    /// the first character — editing in place avoids that extra observed layer.
    @State private var editingItem: WorkoutItem?

    init(workout: Workout, exercise: Exercise) {
        self.workout = workout
        self.exercise = exercise
        let existing = workout.sortedItems.filter { $0.exercise?.persistentModelID == exercise.persistentModelID }
        _weight = State(initialValue: existing.last?.plannedWeight ?? 20)
        _reps = State(initialValue: existing.last?.plannedReps ?? 10)
    }

    private var items: [WorkoutItem] {
        workout.sortedItems.filter { $0.exercise?.persistentModelID == exercise.persistentModelID }
    }

    private var weightBinding: Binding<Double?> {
        Binding(get: { weight }, set: { weight = $0 ?? weight })
    }

    private var repsBinding: Binding<Int?> {
        Binding(get: { reps }, set: { reps = $0 ?? reps })
    }

    var body: some View {
        VStack(spacing: 0) {
            inputBlock
            historyList
        }
        .background(.chalk)
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Готово") { dismiss() }
        }
        // The weight stepper sits right below the sheet's grab area, and a tap
        // there can be captured by the sheet's swipe-to-dismiss gesture instead
        // of the stepper — losing whatever wasn't saved yet. "Готово" above is
        // the only way out.
        .interactiveDismissDisabled()
    }

    private var inputBlock: some View {
        VStack(spacing: 12) {
            WeightInputRow(weight: weightBinding, stepper: $weight)
            RepsInputRow(reps: repsBinding, stepper: $reps)
            if let editingItem {
                HStack(spacing: 12) {
                    Button("Сохранить") {
                        editingItem.plannedWeight = weight
                        editingItem.plannedReps = reps
                        self.editingItem = nil
                    }
                    .font(.sans(15))
                    .buttonStyle(.borderedProminent)
                    .tint(.plateBlue)
                    Button("Отмена") {
                        self.editingItem = nil
                    }
                    .font(.sans(15))
                    .buttonStyle(.bordered)
                }
            } else {
                Button("Добавить подход") {
                    workout.addExercise(exercise, weight: weight, reps: reps, context: context)
                }
                .font(.sans(15))
                .buttonStyle(.borderedProminent)
                .tint(.plateBlue)
            }
        }
        .padding()
    }

    private var historyList: some View {
        List {
            ForEach(items) { item in
                Button {
                    editingItem = item
                    weight = item.plannedWeight ?? weight
                    reps = item.plannedReps ?? reps
                } label: {
                    SetRow(weight: item.plannedWeight ?? 0, reps: item.plannedReps ?? 0)
                }
                .listRowSeparatorTint(.hairline)
                .listRowBackground(Color.chalk)
            }
            .onDelete(perform: delete)
        }
        .scrollContentBackground(.hidden)
        .background(.chalk)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            if editingItem?.persistentModelID == items[index].persistentModelID {
                editingItem = nil
            }
            context.delete(items[index])
        }
    }
}
