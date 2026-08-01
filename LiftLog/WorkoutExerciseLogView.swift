import SwiftUI
import SwiftData

struct WorkoutExerciseLogView: View {
    @Bindable var workout: Workout
    let exercise: Exercise
    let restTimer: RestTimer
    @Environment(\.modelContext) private var context

    @State private var weight: Double?
    @State private var reps: Int?
    @State private var editingSet: WorkoutSet?

    init(workout: Workout, exercise: Exercise, restTimer: RestTimer) {
        self.workout = workout
        self.exercise = exercise
        self.restTimer = restTimer
        let sessionLast = workout.setsFor(exercise).last
        let allTimeLast = exercise.sets.sorted { $0.createdAt < $1.createdAt }.last
        let templateWeight = workout.defaultWeight(for: exercise)
        let templateReps = workout.defaultReps(for: exercise)

        _weight = State(initialValue: templateWeight ?? sessionLast?.weight ?? allTimeLast?.weight)
        _reps = State(initialValue: templateReps ?? sessionLast?.reps ?? allTimeLast?.reps)
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
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                if restTimer.isResting(at: timeline.date) {
                    restBlock
                }
            }
            historyList
        }
        .background(.chalk)
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
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
                workout.logSet(weight: w, reps: r, for: exercise, context: context)

                if let nextWeight = workout.defaultWeight(for: exercise) {
                    weight = nextWeight
                }
                if let nextReps = workout.defaultReps(for: exercise) {
                    reps = nextReps
                }
                restTimer.start(duration: 120, exerciseName: exercise.name)
            }
            .font(.sans(15))
            .buttonStyle(.borderedProminent)
            .tint(.plateBlue)
            .disabled(weight == nil || reps == nil)
        }
        .padding()
    }

    private var restBlock: some View {
        VStack(spacing: 8) {
            RestTimerView(restTimer: restTimer, duration: 120)
            Button("Пропустить отдых") {
                restTimer.skip()
            }
            .font(.sans(13))
            .foregroundStyle(.steel)
        }
        .padding(.bottom, 12)
    }

    private var historyList: some View {
        List {
            ForEach(workout.setsFor(exercise)) { set in
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
