import SwiftUI
import SwiftData

struct WorkoutExerciseLogView: View {
    let workout: Workout
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
        let allTimeLast = exercise.sets.sorted { ($0.createdAt, $0.order) < ($1.createdAt, $1.order) }.last
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
            MuscleMapHero(primaryMuscles: exercise.primaryMuscles, secondaryMuscles: exercise.secondaryMuscles, height: 180)
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
            EditSetView(set: set, workout: workout)
        }
    }

    private var inputBlock: some View {
        VStack(spacing: 12) {
            WeightInputRow(weight: $weight, stepper: weightBinding)
            RepsInputRow(reps: $reps, stepper: repsBinding)
            Button("Добавить подход") {
                guard let w = weight, let r = reps, w > 0, r > 0 else { return }
                workout.logSet(weight: w, reps: r, for: exercise, context: context)

                if let nextWeight = workout.defaultWeight(for: exercise) {
                    weight = nextWeight
                }
                if let nextReps = workout.defaultReps(for: exercise) {
                    reps = nextReps
                }
                restTimer.start(duration: RestTimer.defaultDuration, exerciseName: exercise.name)
                WatchSessionManager.shared.pushSnapshot(for: workout)
            }
            .font(.sans(15))
            .buttonStyle(.borderedProminent)
            .tint(.plateBlue)
            .disabled(weight == nil || reps == nil || (weight ?? 0) <= 0 || (reps ?? 0) <= 0)
        }
        .padding()
    }

    private var restBlock: some View {
        VStack(spacing: 8) {
            RestTimerView(restTimer: restTimer, duration: RestTimer.defaultDuration)
            Button("Пропустить отдых") {
                restTimer.skip()
                WatchSessionManager.shared.pushSnapshot(for: workout)
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
