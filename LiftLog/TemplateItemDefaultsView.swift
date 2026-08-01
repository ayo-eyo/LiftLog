import SwiftUI
import SwiftData

struct TemplateItemDefaultsView: View {
    @Bindable var template: WorkoutTemplate
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

    var body: some View {
        NavigationStack {
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
    }

    private var inputBlock: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Вес").font(.sans(16)).foregroundStyle(.ink)
                Spacer()
                TextField("кг", value: $weight, format: .number)
                    .font(.mono(17))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 80)
                    .padding(.vertical, 8)
                    .background(.chalkDeep, in: .rect(cornerRadius: 8))
                Stepper("", value: $weight, in: 0...500, step: 0.5).labelsHidden()
            }
            HStack {
                Text("Повторы").font(.sans(16)).foregroundStyle(.ink)
                Spacer()
                TextField("", value: $reps, format: .number)
                    .font(.mono(17))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 80)
                    .padding(.vertical, 8)
                    .background(.chalkDeep, in: .rect(cornerRadius: 8))
                Stepper("", value: $reps, in: 1...100).labelsHidden()
            }
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
                HStack {
                    Text(item.defaultWeight.formatted(.number) + " кг")
                        .font(.mono(15)).foregroundStyle(.ink)
                    Spacer()
                    Text("× \(item.defaultReps)")
                        .font(.mono(15)).foregroundStyle(.steel)
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
            context.delete(items[index])
        }
    }
}
