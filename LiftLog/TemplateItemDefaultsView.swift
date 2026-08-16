import SwiftUI
import SwiftData

struct TemplateItemDefaultsView: View {
    let template: WorkoutTemplate
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var weight: Double
    @State private var reps: Int
    

    init(template: WorkoutTemplate, exercise: Exercise) {
        self.template = template
        self.exercise = exercise
        let existing = template.sortedItems.filter { $0.exercise?.persistentModelID == exercise.persistentModelID }
        _weight = State(initialValue: existing.last?.defaultWeight ?? 20)
        _reps = State(initialValue: existing.last?.defaultReps ?? 10)
    }

    private var items: [TemplateItem] {
        template.sortedItems.filter { $0.exercise?.persistentModelID == exercise.persistentModelID }
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
    }

    private var inputBlock: some View {
        VStack(spacing: 12) {
            WeightInputRow(weight: weightBinding, stepper: $weight)
            RepsInputRow(reps: repsBinding, stepper: $reps)
            Button("Добавить подход") {
                template.addExercise(exercise, weight: weight, reps: reps, context: context)
            }
            .font(.sans(15))
            .buttonStyle(.borderedProminent)
            .tint(.plateBlue)
        }
        .padding()
    }

    private var historyList: some View {
        List {
            ForEach(items) { item in
                SetRow(weight: item.defaultWeight, reps: item.defaultReps)
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
            context.delete(items[index])
        }
    }
}
