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
    // Only commit to the model when the field holds a valid positive value.
    @State private var weight: Double?
    @State private var reps: Int?

    init(set: WorkoutSet, workout: Workout? = nil) {
        self.set = set
        self.workout = workout
        _weight = State(initialValue: set.weight)
        _reps = State(initialValue: set.reps)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                WeightInputRow(weight: $weight)
                RepsInputRow(reps: $reps)
                Button("Удалить подход", role: .destructive) {
                    context.delete(set)
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
            if let newValue, newValue > 0 { set.weight = newValue }
        }
        .onChange(of: reps) { _, newValue in
            if let newValue, newValue > 0 { set.reps = newValue }
        }
        .onDisappear {
            pushWatchUpdate()
        }
    }

    private func commitAndDismiss() {
        if let weight, weight > 0 { set.weight = weight }
        if let reps, reps > 0 { set.reps = reps }
        dismiss()
    }

    private func pushWatchUpdate() {
        guard let workout else { return }
        WatchSessionManager.shared.pushSnapshot(for: workout)
    }
}
