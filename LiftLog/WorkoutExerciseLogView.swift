import SwiftUI
import SwiftData

struct WorkoutExerciseLogView: View {
    @Bindable var workout: Workout
    let exercise: Exercise
    @Environment(\.modelContext) private var context

    @State private var weight: Double?
    @State private var reps: Int?

    init(workout: Workout, exercise: Exercise) {
        self.workout = workout
        self.exercise = exercise
        let sessionLast = workout.setsFor(exercise).last
        let allTimeLast = exercise.sets.sorted { $0.createdAt < $1.createdAt }.last
        let prefill = sessionLast ?? allTimeLast
        _weight = State(initialValue: prefill?.weight)
        _reps = State(initialValue: prefill?.reps)
    }

    private var weightBinding: Binding<Double> {
        Binding(get: { weight ?? 0 }, set: { weight = $0 })
    }

    private var repsBinding: Binding<Int> {
        Binding(get: { reps ?? 0 }, set: { reps = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            inputBlock
            historyList
        }
        .background(.chalk)
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
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
                workout.logSet(weight: w, reps: r, for: exercise, context: context)
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
            ForEach(workout.setsFor(exercise)) { set in
                HStack {
                    Text(set.weight.formatted(.number) + " кг")
                        .font(.mono(15)).foregroundStyle(.ink)
                    Spacer()
                    Text("× \(set.reps)")
                        .font(.mono(15)).foregroundStyle(.steel)
                }
                .listRowSeparatorTint(.hairline)
                .listRowBackground(Color.chalk)
            }
        }
        .scrollContentBackground(.hidden)
        .background(.chalk)
    }
}
