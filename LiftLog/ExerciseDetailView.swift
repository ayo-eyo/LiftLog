import SwiftUI
import SwiftData

struct ExerciseDetailView: View {
    @Bindable var exercise: Exercise
    @Environment(\.modelContext) private var context

    @State private var weight: Double?
    @State private var reps: Int?
    @State private var editingSet: WorkoutSet?

    init(exercise: Exercise) {
        self.exercise = exercise
        let last = exercise.sets.sorted { $0.createdAt < $1.createdAt }.last
        _weight = State(initialValue: last?.weight)
        _reps = State(initialValue: last?.reps)
    }

    private var weightBinding: Binding<Double> {
        Binding(get: { weight ?? 0 }, set: { weight = $0 })
    }

    private var repsBinding: Binding<Int> {
        Binding(get: { reps ?? 0 }, set: { reps = $0 })
    }

    private var sets: [WorkoutSet] {
        exercise.sets.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            inputBlock
            historyList
        }
        .background(.chalk)
        .navigationTitle(exercise.name)
        .sheet(item: $editingSet) { set in
            EditSetView(set: set)
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
                Stepper("", value: weightBinding, in: 0...500, step: 0.5)
                    .labelsHidden()
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
                Stepper("", value: repsBinding, in: 1...100)
                    .labelsHidden()
            }
            Button("Добавить подход") {
                guard let w = weight, let r = reps else { return }
                exercise.addSet(weight: w, reps: r, context: context)
            }
            .font(.sans(15))
            .buttonStyle(.borderedProminent)
            .tint(.plateBlue)
            .disabled(weight == nil || reps == nil)
        }
        .padding()
    }

    private var historyList: some View {
        List {
            ForEach(sets) { set in
                Button {
                    editingSet = set
                } label: {
                    HStack {
                        Text(set.weight.formatted(.number) + " кг")
                            .font(.mono(15)).foregroundStyle(.ink)
                        Spacer()
                        Text("× \(set.reps)")
                            .font(.mono(15)).foregroundStyle(.steel)
                    }
                }
                .listRowSeparatorTint(.hairline)
                .listRowBackground(Color.chalk)
            }
        }
        .scrollContentBackground(.hidden)
        .background(.chalk)
    }
}
