import SwiftUI
import SwiftData

/// Bubbles up to `RootTabView` so it can hide its own global "start" accessory
/// while a plan screen is already showing its own «Начать» button for the same
/// action — otherwise the user sees two start buttons on screen at once.
struct HidesStartAccessoryPreferenceKey: PreferenceKey {
    static var defaultValue: Bool { false }
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

enum WorkoutSheet: Identifiable {
    case picker
    case defaults(Exercise)

    var id: String {
        switch self {
        case .picker: return "picker"
        case .defaults(let exercise): return "defaults-\(exercise.persistentModelID)"
        }
    }
}

/// One screen for all three workout states (plan / active / completed) — see
/// FR-2 in plans/features/delete-fixture/requirements.md. Pushed from
/// `WorkoutListView` for browsing/editing; presented as a `fullScreenCover`
/// root by `RootTabView` for the focused start/log/finish flow. Doesn't wrap
/// itself in a `NavigationStack` — whichever context presents it owns that,
/// the same way the old pushed template/summary screens relied on their
/// parent's stack.
struct WorkoutDetailView: View {
    @Bindable var workout: Workout
    let restTimer: RestTimer
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var activeSheet: WorkoutSheet?
    @State private var pendingDeleteExercise: Exercise?
    @State private var editingSet: WorkoutSet?
    /// Picking an exercise from `.picker` used to jump straight to
    /// `.defaults(exercise)` by reassigning `activeSheet` to a different non-nil
    /// value while its sheet was still on screen. `.sheet(item:)` doesn't treat
    /// that as a clean swap — it can leave a second presentation stacked behind
    /// the first, which then fights the new one for layout. Routing through a
    /// full dismiss (`activeSheet = nil`) and presenting `.defaults` from
    /// `onDismiss` instead avoids that.
    @State private var pendingDefaultsExercise: Exercise?

    @Query(filter: #Predicate<Workout> { $0.startedAt != nil && $0.completedAt == nil })
    private var activeWorkouts: [Workout]
    @Query(sort: \Workout.sortIndex) private var allWorkouts: [Workout]

    private var groupedItems: [(exercise: Exercise, items: [WorkoutItem])] {
        workout.groupedItems
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if workout.completedAt != nil {
                completedList
            } else {
                editableList
                bottomButtons
            }
        }
        .background(.chalk)
        .navigationTitle(workout.name.isEmpty ? workout.date.formatted(date: .abbreviated, time: .shortened) : workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(item: $activeSheet, onDismiss: {
            if let exercise = pendingDefaultsExercise {
                pendingDefaultsExercise = nil
                activeSheet = .defaults(exercise)
            }
        }) { sheet in
            sheetContent(for: sheet)
        }
        .sheet(item: $editingSet) { set in
            EditSetView(set: set)
        }
        .confirmationDialog(
            "Удалить упражнение вместе с уже залогированными подходами?",
            isPresented: Binding(get: { pendingDeleteExercise != nil }, set: { if !$0 { pendingDeleteExercise = nil } }),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let exercise = pendingDeleteExercise {
                    workout.deleteExercise(exercise, context: context)
                }
                pendingDeleteExercise = nil
            }
            Button("Отмена", role: .cancel) { pendingDeleteExercise = nil }
        }
        .onAppear {
            if workout.isActive {
                WatchSessionManager.shared.pushSnapshot(for: workout)
            }
        }
        .preference(key: HidesStartAccessoryPreferenceKey.self, value: showsOwnStartButton)
    }

    /// Whether this screen is showing its own «Начать» button — the exact
    /// condition `bottomButtons` uses, shared so the global accessory can hide
    /// itself instead of duplicating the button.
    private var showsOwnStartButton: Bool {
        workout.startedAt == nil && !workout.items.isEmpty && activeWorkouts.isEmpty
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 8) {
            TextField("Название тренировки", text: $workout.name)
                .font(.display(24))
                .foregroundStyle(.ink)
            DatePicker("Дата", selection: $workout.date, displayedComponents: [.date, .hourAndMinute])
                .font(.sans(13))
                .foregroundStyle(.steel)
                .datePickerStyle(.compact)
        }
        .padding()
    }

    // MARK: Editable content (plan / active)

    private var editableList: some View {
        List {
            ForEach(groupedItems, id: \.exercise.persistentModelID) { group in
                NavigationLink {
                    if workout.isActive {
                        WorkoutExerciseLogView(workout: workout, exercise: group.exercise, restTimer: restTimer)
                    } else {
                        WorkoutItemDefaultsView(workout: workout, exercise: group.exercise)
                    }
                } label: {
                    exerciseRow(group)
                }
                .listRowBackground(Color.chalk)
                .listRowSeparatorTint(.hairline)
            }
            .onMove(perform: moveExercise)
            .onDelete(perform: deleteExercise)
        }
        .scrollContentBackground(.hidden)
        .background(.chalk)
    }

    private func exerciseRow(_ group: (exercise: Exercise, items: [WorkoutItem])) -> some View {
        HStack(spacing: 11) {
            ExerciseThumbnail(primaryMuscles: group.exercise.primaryMuscles, secondaryMuscles: group.exercise.secondaryMuscles, size: 44, cornerRadius: 9)
            VStack(alignment: .leading, spacing: 4) {
                Text(group.exercise.name).font(.sans(16)).foregroundStyle(.ink)
                if workout.isActive {
                    let count = workout.setsFor(group.exercise).count
                    Text("\(count) \(RussianPlural.form(count, "подход", "подхода", "подходов"))")
                        .font(.mono(13))
                        .foregroundStyle(.steel)
                } else {
                    Text(plannedSummary(group.items))
                        .font(.mono(12))
                        .foregroundStyle(.steel)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }

    private func plannedSummary(_ items: [WorkoutItem]) -> String {
        items.map { item -> String in
            guard let weight = item.plannedWeight, let reps = item.plannedReps else { return "без плана" }
            return "\(weight.formatted(.number)) кг × \(reps)"
        }.joined(separator: " · ")
    }

    private var bottomButtons: some View {
        VStack(spacing: 10) {
            Button("Добавить упражнение") { activeSheet = .picker }
                .font(.sans(15))
                .buttonStyle(.bordered)
                .tint(.plateBlue)

            if workout.startedAt == nil && !workout.items.isEmpty {
                if showsOwnStartButton {
                    Button("Начать") { start() }
                        .font(.sans(15))
                        .buttonStyle(.borderedProminent)
                        .tint(.plateBlue)
                } else {
                    Text("Тренировка уже идёт — заверши её, чтобы начать эту")
                        .font(.sans(13))
                        .foregroundStyle(.steel)
                }
            }
        }
        .padding()
    }

    // MARK: Completed content

    private var completedList: some View {
        List {
            ForEach(workout.orderedExercises) { exercise in
                exerciseSection(exercise)
            }
        }
        .scrollContentBackground(.hidden)
        .background(.chalk)
    }

    private func exerciseSection(_ exercise: Exercise) -> some View {
        Section {
            ForEach(workout.setsFor(exercise)) { set in
                Button {
                    editingSet = set
                } label: {
                    SetRow(weight: set.weight, reps: set.reps, fontSize: 14)
                }
            }
            NavigationLink("Вся история упражнения") {
                ExerciseDetailView(exercise: exercise)
            }
            .font(.sans(14))
            .foregroundStyle(.plateBlue)
        } header: {
            Text(exercise.name).font(.sans(15)).foregroundStyle(.ink)
        }
        .listRowBackground(Color.chalk)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if workout.completedAt == nil && groupedItems.count > 1 {
            ToolbarItem(placement: .navigationBarTrailing) { EditButton() }
        }
        if !workout.isActive {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    copyWorkout()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityIdentifier("workoutDetail.copyButton")
            }
        }
        if workout.isActive {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть") { closeIfEmpty() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Завершить") { finish() }
            }
        }
    }

    @ViewBuilder
    private func sheetContent(for sheet: WorkoutSheet) -> some View {
        switch sheet {
        case .picker:
            ExercisePickerView(excluding: Set(workout.orderedExercises.compactMap { $0.catalogID })) { exercise in
                if workout.isActive {
                    workout.addExercise(exercise, context: context)
                    activeSheet = nil
                    WatchSessionManager.shared.pushSnapshot(for: workout)
                } else {
                    pendingDefaultsExercise = exercise
                    activeSheet = nil
                }
            }
        case .defaults(let exercise):
            NavigationStack {
                WorkoutItemDefaultsView(workout: workout, exercise: exercise)
            }
        }
    }

    // MARK: Actions

    private func start() {
        workout.start()
        WatchSessionManager.shared.pushSnapshot(for: workout)
    }

    private func finish() {
        restTimer.skip()
        workout.finish()
        HealthKitManager.save(workout)
        WatchSessionManager.shared.pushSnapshot(for: nil)
        dismiss()
    }

    private func closeIfEmpty() {
        if workout.items.isEmpty {
            context.delete(workout)
            WatchSessionManager.shared.pushSnapshot(for: nil)
        }
        dismiss()
    }

    /// Creates the copy and returns to the list, where it now sorts to the top,
    /// instead of pushing straight into it: pushing a second `WorkoutDetailView`
    /// from within a `WorkoutDetailView` over `.navigationDestination(item:)`
    /// hung the app — the destination is the same view type as the presenter,
    /// and having both live on the stack sent SwiftUI's view-graph diffing into
    /// a runaway loop, independent of the copy's exercise count.
    private func copyWorkout() {
        let newSortIndex = (allWorkouts.map(\.sortIndex).min() ?? 0) - 1
        _ = Workout.copy(of: workout, sortIndex: newSortIndex, context: context)
        dismiss()
    }

    private func moveExercise(from source: IndexSet, to destination: Int) {
        workout.moveExercise(from: source, to: destination)
    }

    private func deleteExercise(at offsets: IndexSet) {
        let groups = groupedItems
        for index in offsets {
            let exercise = groups[index].exercise
            if workout.setsFor(exercise).isEmpty {
                workout.deleteExercise(exercise, context: context)
            } else {
                pendingDeleteExercise = exercise
            }
        }
    }
}
