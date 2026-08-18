import SwiftUI
import SwiftData

enum WorkoutSheet: Identifiable {
    case picker
    case defaults(Exercise)
    case editSet(WorkoutSet)

    var id: String {
        switch self {
        case .picker: return "picker"
        case .defaults(let exercise): return "defaults-\(exercise.persistentModelID)"
        case .editSet(let set): return "editSet-\(set.persistentModelID)"
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
    /// Multiple rows can be swipe/edit-deleted in one gesture (`EditButton` mode) — every
    /// one that already has logged sets needs its own confirmation, not just the last.
    @State private var pendingDeleteExercises: [Exercise] = []
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
                if workout.status == .plan {
                    bottomButtons
                }
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
        .confirmationDialog(
            pendingDeleteTitle,
            isPresented: Binding(get: { !pendingDeleteExercises.isEmpty }, set: { if !$0 { pendingDeleteExercises = [] } }),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                for exercise in pendingDeleteExercises {
                    workout.deleteExercise(exercise, context: context)
                }
                pendingDeleteExercises = []
            }
            Button("Отмена", role: .cancel) { pendingDeleteExercises = [] }
        }
        .onAppear {
            if workout.isActive {
                WatchSessionManager.shared.pushSnapshot(for: workout)
            }
        }
    }

    /// Whether this screen is showing its own «Начать» button, vs. the "another
    /// workout is already active" message — `bottomButtons` is the only reader.
    private var showsOwnStartButton: Bool {
        workout.startedAt == nil && !workout.items.isEmpty && activeWorkouts.isEmpty
    }

    private var pendingDeleteTitle: String {
        let count = pendingDeleteExercises.count
        return "Удалить \(count) \(RussianPlural.form(count, "упражнение", "упражнения", "упражнений")) вместе с уже залогированными подходами?"
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 8) {
            if workout.status == .plan {
                TextField("Название тренировки", text: $workout.name)
                    .font(.display(24))
                    .foregroundStyle(.ink)
                DatePicker("Дата", selection: $workout.date, displayedComponents: [.date, .hourAndMinute])
                    .font(.sans(13))
                    .foregroundStyle(.steel)
                    .datePickerStyle(.compact)
            } else {
                Text(workout.name.isEmpty ? workout.date.formatted(date: .abbreviated, time: .shortened) : workout.name)
                    .font(.display(24))
                    .foregroundStyle(.ink)
                // Skipped when there's no name — the title above is already the date,
                // repeating it here would be the same string a third time alongside
                // the nav bar title.
                if !workout.name.isEmpty {
                    Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.sans(13))
                        .foregroundStyle(.steel)
                }
            }
        }
        .padding()
    }

    // MARK: Editable content (plan / active)

    private var editableList: some View {
        List {
            // Reordering stays available once a workout is active (the exercise
            // list doesn't need to be locked to reorder), but add/delete are
            // plan-only — so `.onDelete` is attached conditionally rather than
            // unconditionally like `.onMove`.
            if workout.status == .plan {
                exerciseRows.onDelete(perform: deleteExercise)
            } else {
                exerciseRows
            }
        }
        .scrollContentBackground(.hidden)
        .background(.chalk)
    }

    private var exerciseRows: some DynamicViewContent {
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

    /// Only called when `workout.status == .plan` — an active/completed workout has
    /// nothing to show here, so the caller skips this entirely rather than rendering
    /// an empty padded `VStack`.
    private var bottomButtons: some View {
        VStack(spacing: 10) {
            Button("Добавить упражнение") { activeSheet = .picker }
                .font(.sans(15))
                .buttonStyle(.bordered)
                .tint(.plateBlue)

            if !workout.items.isEmpty {
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
                    activeSheet = .editSet(set)
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
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        if !workout.isActive {
            ToolbarItem(placement: .topBarTrailing) {
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
            // Only reachable via the "Добавить упражнение" button, which is
            // plan-only — so this always routes to setting planned defaults,
            // never straight into `workout.addExercise`.
            ExercisePickerView(excluding: Set(workout.orderedExercises.compactMap { $0.catalogID })) { exercise in
                pendingDefaultsExercise = exercise
                activeSheet = nil
            }
        case .defaults(let exercise):
            NavigationStack {
                WorkoutItemDefaultsView(workout: workout, exercise: exercise)
            }
        case .editSet(let set):
            EditSetView(set: set)
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
        Task { await HealthKitManager.save(workout) }
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
        // A one-off fetch instead of a live `@Query` over every workout — this screen
        // only needs the top sort index at the moment of copying, not a standing
        // subscription that invalidates the whole screen on any workout's change.
        var descriptor = FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.sortIndex)])
        descriptor.fetchLimit = 1
        let minSortIndex = (try? context.fetch(descriptor))?.first?.sortIndex ?? 0
        _ = Workout.copy(of: workout, sortIndex: minSortIndex - 1, context: context)
        dismiss()
    }

    private func moveExercise(from source: IndexSet, to destination: Int) {
        workout.moveExercise(from: source, to: destination)
    }

    private func deleteExercise(at offsets: IndexSet) {
        let groups = groupedItems
        var needsConfirmation: [Exercise] = []
        for index in offsets {
            let exercise = groups[index].exercise
            if workout.setsFor(exercise).isEmpty {
                workout.deleteExercise(exercise, context: context)
            } else {
                needsConfirmation.append(exercise)
            }
        }
        if !needsConfirmation.isEmpty {
            pendingDeleteExercises = needsConfirmation
        }
    }
}

#Preview("План") {
    let container = PreviewSupport.container()
    let context = container.mainContext
    let bench = Exercise(name: "Жим лёжа")
    let squat = Exercise(name: "Присед")
    context.insert(bench)
    context.insert(squat)
    let workout = Workout(name: "Грудь и ноги")
    context.insert(workout)
    workout.addExercise(bench, weight: 60, reps: 8, context: context)
    workout.addExercise(squat, weight: 100, reps: 5, context: context)

    return NavigationStack {
        WorkoutDetailView(workout: workout, restTimer: PreviewSupport.restTimer())
    }
    .modelContainer(container)
}

#Preview("Идёт, крупный текст") {
    let container = PreviewSupport.container()
    let context = container.mainContext
    let bench = Exercise(name: "Жим лёжа")
    context.insert(bench)
    let workout = Workout(name: "Грудь")
    context.insert(workout)
    workout.addExercise(bench, weight: 60, reps: 8, context: context)
    workout.start()
    workout.logSet(weight: 60, reps: 8, for: bench, context: context)

    return NavigationStack {
        WorkoutDetailView(workout: workout, restTimer: PreviewSupport.restTimer())
    }
    .modelContainer(container)
    .dynamicTypeSize(.accessibility3)
}
