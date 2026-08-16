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
            WeightInputRow(weight: $weight, stepper: weightBinding)
            RepsInputRow(reps: $reps, stepper: repsBinding)
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
                    SetRow(weight: set.weight, reps: set.reps)
                }
                .listRowSeparatorTint(.hairline)
                .listRowBackground(Color.chalk)
            }
        }
        .scrollContentBackground(.hidden)
        .background(.chalk)
    }
}
