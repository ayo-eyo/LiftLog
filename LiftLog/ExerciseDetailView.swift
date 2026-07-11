import SwiftUI
import SwiftData

struct ExerciseDetailView: View {
    @Bindable var exercise: Exercise
    @Environment(\.modelContext) private var context

    @State private var weight: Double?
    @State private var reps: Int?
    
    init(exercise: Exercise) {
        self.exercise = exercise
        let last = exercise.sets.sorted { $0.createdAt < $1.createdAt }.last
        _weight = State(initialValue: last?.weight)
        _reps = State(initialValue: last?.reps)
    }

    private var sets: [WorkoutSet] {
        exercise.sets.sorted { $0.createdAt < $1.createdAt }
    }
    
    private var weightBinding: Binding<Double> {
        Binding(
            get: { weight ?? 0 },
            set: { weight = $0 }
        )
    }
    
    private var repsBinding: Binding<Int> {
        Binding(
            get: { reps ?? 0 },
            set: { reps = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            inputBlock
            historyList
        }
        .navigationTitle(exercise.name)
    }

    private var inputBlock: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Вес")
                Spacer()
                TextField("кг", value: $weight, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 80)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6), in: .rect(cornerRadius: 8))
                Stepper("", value: weightBinding, in: 0...500, step: 0.5)
                    .labelsHidden()
            }

            HStack {
                Text("Повторы")
                Spacer()
                TextField("кол-во", value: $reps, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 80)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6), in: .rect(cornerRadius: 8))
                Stepper("", value: repsBinding, in: 1...100)
                    .labelsHidden()
            }

            Button("Добавить подход") {
                guard let w = weight, let r = reps else { return }
                exercise.addSet(weight: w, reps: r, context: context)
            }
            .disabled(weight == nil || reps == nil)
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var historyList: some View {
        List {
            ForEach(sets) { set in
                HStack {
                    Text(set.weight.formatted(.number) + " кг")
                    Spacer()
                    Text("× \(set.reps)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
