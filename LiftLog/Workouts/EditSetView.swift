import SwiftUI
import SwiftData

struct EditSetView: View {
    @Bindable var set: WorkoutSet
    /// nil when editing a set logged outside any workout (`ExerciseDetailView`'s
    /// standalone-logging flow) — nothing to push to the watch in that case.
    let workout: Workout?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    // Local, clearable state: writing straight through to `set.weight`/`set.reps` with a
    // "revert to old value on nil" binding (the previous approach) makes the field
    // un-clearable, since every keystroke that empties it snaps back to the old value.
    // Only commit to the model once the field holds a valid value — weight may be 0
    // (bodyweight exercises), reps must stay positive.
    @State private var weight: Double?
    @State private var reps: Int?
    /// Whether anything was actually written to the model, so closing the sheet without
    /// touching a field doesn't bump `Workout.version` for nothing.
    @State private var didEdit = false

    init(set: WorkoutSet, workout: Workout? = nil) {
        self.set = set
        self.workout = workout
        _weight = State(initialValue: set.weight)
        _reps = State(initialValue: set.reps)
    }

    private var weightStepper: Binding<Double> {
        Binding(get: { weight ?? 0 }, set: { weight = $0 })
    }

    private var repsStepper: Binding<Int> {
        Binding(get: { reps ?? 0 }, set: { reps = $0 })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                WeightInputRow(weight: $weight, stepper: weightStepper, accessibilityID: "editSet.weight")
                RepsInputRow(reps: $reps, stepper: repsStepper, accessibilityID: "editSet.reps")
                Button("Удалить подход", role: .destructive) {
                    WorkoutSet.delete(set, context: context)
                    didEdit = true
                    pushWatchUpdate()
                    dismiss()
                }
                .font(.sans(15))
                Spacer()
            }
            .padding()
            .background(.chalk)
            .navigationTitle("Подход")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Готово") { commitAndDismiss() }
            }
        }
        .onChange(of: weight) { _, newValue in
            if let newValue, newValue >= 0, newValue != set.weight {
                set.weight = newValue
                didEdit = true
            }
        }
        .onChange(of: reps) { _, newValue in
            if let newValue, newValue > 0, newValue != set.reps {
                set.reps = newValue
                didEdit = true
            }
        }
        .onDisappear {
            pushWatchUpdate()
        }
    }

    private func commitAndDismiss() {
        if let weight, weight >= 0, weight != set.weight {
            set.weight = weight
            didEdit = true
        }
        if let reps, reps > 0, reps != set.reps {
            set.reps = reps
            didEdit = true
        }
        dismiss()
    }

    private func pushWatchUpdate() {
        guard let workout else { return }
        // An edited set changes what the watch shows, so it moves the version the same
        // way logging one does — see `Workout.bumpVersion`.
        if didEdit { workout.bumpVersion() }
        WatchSessionManager.shared.pushSnapshot(for: workout)
    }
}
