import SwiftUI
import SwiftData

/// «Следующая тренировка» (plans/features/progression, FR-2): what the finished workout's
/// plan turns into next time. Per exercise — was the plan done, the volume against plan,
/// and each position as «60×8 → 62,5×8». Every number can be changed before saving;
/// nothing touches the store until «Сохранить план», which creates the next workout as a
/// plan. Presented as a sheet by `WorkoutDetailView`, in its own `NavigationStack`.
struct NextWorkoutPlanView: View {
    let workout: Workout
    /// Called after «Сохранить план» or «Пропустить» — the presenter closes the sheet and
    /// decides what happens to the screen under it.
    let onClose: () -> Void
    @Environment(\.modelContext) private var context

    private let progressions: [ExerciseProgression]
    /// The next plan as it stands — the rule's suggestion until a position is edited.
    @State private var next: [PersistentIdentifier: [ProgressionPosition]]
    @State private var editing: EditedPosition?

    private struct EditedPosition: Identifiable {
        let exerciseID: PersistentIdentifier
        let index: Int
        var id: String { "\(exerciseID)-\(index)" }
    }

    init(workout: Workout, onClose: @escaping () -> Void) {
        self.workout = workout
        self.onClose = onClose
        let defaults = ProgressionDefaults.load()
        let progressions = WorkoutProgression.progressions(for: workout) { $0.progressionSettings(defaults: defaults) }
        self.progressions = progressions
        _next = State(initialValue: Dictionary(uniqueKeysWithValues: progressions.map { ($0.id, $0.suggested) }))
    }

    var body: some View {
        List {
            ForEach(Array(progressions.enumerated()), id: \.element.id) { index, progression in
                exerciseSection(progression, index: index)
            }
        }
        .scrollContentBackground(.hidden)
        .background(.chalk)
        .navigationTitle("Next workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Skip") { onClose() }
                    .accessibilityIdentifier("nextPlan.skip")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save plan") { save() }
                    .accessibilityIdentifier("nextPlan.save")
            }
        }
        .sheet(item: $editing) { edited in
            NavigationStack {
                NextPositionEditView(position: binding(for: edited))
            }
            .presentationDetents([.medium])
        }
        // Not interactively dismissable: a swipe down would leave the presenter not
        // knowing whether to close the workout screen under it too.
        .interactiveDismissDisabled()
    }

    // MARK: Sections

    private func exerciseSection(_ progression: ExerciseProgression, index: Int) -> some View {
        Section {
            let positions = next[progression.id] ?? progression.current
            ForEach(Array(progression.current.enumerated()), id: \.offset) { offset, current in
                let planned = offset < positions.count ? positions[offset] : current
                Button {
                    editing = EditedPosition(exerciseID: progression.id, index: offset)
                } label: {
                    positionRow(current: current, next: planned, progression: progression)
                }
                .accessibilityIdentifier("nextPlan.position.\(index).\(offset)")
            }
        } header: {
            header(progression)
                .accessibilityIdentifier("nextPlan.exercise.\(index)")
        }
        .listRowBackground(Color.chalk)
    }

    private func header(_ progression: ExerciseProgression) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(progression.exercise.displayName)
                .font(.sans(15))
                .foregroundStyle(.ink)
            if progression.hasPlan {
                HStack(spacing: 6) {
                    Image(systemName: progression.isFulfilled ? "checkmark.circle.fill" : "minus.circle")
                        .foregroundStyle(progression.isFulfilled ? Color.plateGreen : Color.steel)
                    Text(progression.isFulfilled ? "Plan done" : "Plan not done")
                        .font(.sans(13))
                        .foregroundStyle(.steel)
                    Spacer()
                    Text(volumeText(progression))
                        .font(.mono(12))
                        .foregroundStyle(.steel)
                }
            }
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }

    private func positionRow(current: ProgressionPosition, next: ProgressionPosition, progression: ExerciseProgression) -> some View {
        let isChanged = next != current
        let isHeldAtLimit = progression.isBodyweight && progression.isFulfilled && !isChanged
            && (current.reps ?? 0) >= progression.settings.repLimit
        return HStack(spacing: 8) {
            Text(Self.label(current))
                .font(.mono(15))
                .foregroundStyle(isChanged ? Color.steel : Color.ink)
            if isChanged {
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.plateBlue)
                Text(Self.label(next))
                    .font(.mono(15))
                    .foregroundStyle(.ink)
            }
            Spacer()
            if isHeldAtLimit {
                Text("limit")
                    .font(.sans(12))
                    .foregroundStyle(.steel)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isChanged
            ? String(localized: "\(Self.label(current)), next time \(Self.label(next))")
            : Self.label(current))
    }

    // MARK: Text

    /// «62,5×8», «×12» for bodyweight, «без плана» for a position with no reps.
    static func label(_ position: ProgressionPosition) -> String {
        guard let reps = position.reps else { return String(localized: "no plan") }
        guard let weight = position.weight, weight > 0 else { return "×\(reps)" }
        return "\(weight.formatted(.number))×\(reps)"
    }

    /// «2 040 / 1 920 кг» or, for bodyweight, «повторов: 42 / 40».
    private func volumeText(_ progression: ExerciseProgression) -> String {
        if progression.isBodyweight {
            let logged = Int(progression.loggedVolume)
            let planned = Int(progression.plannedVolume)
            return String(localized: "reps: \(logged) / \(planned)")
        }
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
        return String(localized: "\(progression.loggedVolume.formatted(format)) / \(progression.plannedVolume.formatted(format)) kg")
    }

    // MARK: Actions

    private func binding(for edited: EditedPosition) -> Binding<ProgressionPosition> {
        Binding(
            get: {
                next[edited.exerciseID]?[safe: edited.index]
                    ?? progressions.first { $0.id == edited.exerciseID }?.current[safe: edited.index]
                    ?? ProgressionPosition()
            },
            set: { newValue in
                guard var positions = next[edited.exerciseID], edited.index < positions.count else { return }
                positions[edited.index] = newValue
                next[edited.exerciseID] = positions
            }
        )
    }

    private func save() {
        // Top of the list, like «Копировать» from a workout screen.
        var descriptor = FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.sortIndex)])
        descriptor.fetchLimit = 1
        let minSortIndex = (try? context.fetch(descriptor))?.first?.sortIndex ?? 0
        _ = Workout.copy(of: workout, positions: next, sortIndex: minSortIndex - 1, context: context)
        try? context.save()
        // The watch lists plans and can start them.
        WatchSessionManager.shared.refresh()
        onClose()
    }
}

/// Weight and reps of one position of the next plan, with the shared inputs from
/// `SetInputViews.swift`. Plain values — nothing is written to the store from here.
private struct NextPositionEditView: View {
    @Binding var position: ProgressionPosition
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            WeightInputRow(
                weight: $position.weight,
                stepper: Binding(get: { position.weight ?? 0 }, set: { position.weight = $0 }),
                accessibilityID: "nextPlan.weightInput"
            )
            RepsInputRow(
                reps: $position.reps,
                stepper: Binding(get: { position.reps ?? 1 }, set: { position.reps = $0 }),
                accessibilityID: "nextPlan.repsInput"
            )
        }
        .scrollContentBackground(.hidden)
        .background(.chalk)
        .navigationTitle("Next time")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("nextPlan.editDone")
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    let container = PreviewSupport.container()
    let context = container.mainContext
    let bench = Exercise(name: "Bench press", catalogID: "Barbell_Bench_Press_-_Medium_Grip")
    let pullUp = Exercise(name: "Pull-up")
    context.insert(bench)
    context.insert(pullUp)
    let workout = Workout(name: "Chest")
    context.insert(workout)
    workout.addExercise(bench, weight: 60, reps: 8, context: context)
    workout.addExercise(bench, weight: 60, reps: 8, context: context)
    workout.addExercise(pullUp, weight: 0, reps: 10, context: context)
    workout.start()
    workout.logSet(weight: 60, reps: 8, for: bench, context: context)
    workout.logSet(weight: 60, reps: 8, for: bench, context: context)
    workout.logSet(weight: 0, reps: 8, for: pullUp, context: context)
    workout.finish()

    return NavigationStack {
        NextWorkoutPlanView(workout: workout, onClose: {})
    }
    .modelContainer(container)
}
