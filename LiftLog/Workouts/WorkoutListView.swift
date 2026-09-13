import SwiftUI
import SwiftData

struct WorkoutListView: View {
    let restTimer: RestTimer
    @Query(sort: [SortDescriptor(\Workout.sortIndex), SortDescriptor(\Workout.date, order: .reverse)])
    private var workouts: [Workout]
    @Environment(\.modelContext) private var context
    @State private var newWorkout: Workout?
    @State private var isShowingData = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(workouts) { workout in
                    NavigationLink {
                        WorkoutDetailView(workout: workout, restTimer: restTimer)
                    } label: {
                        WorkoutRow(workout: workout)
                    }
                    .listRowBackground(Color.chalk)
                    .listRowSeparatorTint(.hairline)
                    .swipeActions(edge: .leading) {
                        Button {
                            copyWorkout(workout)
                        } label: {
                            Label("Копировать", systemImage: "doc.on.doc")
                        }
                        .tint(.plateBlue)
                    }
                    .contextMenu {
                        Button {
                            copyWorkout(workout)
                        } label: {
                            Label("Копировать", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            delete(workout)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: delete)
                .onMove(perform: move)
            }
            .scrollContentBackground(.hidden)
            .background(.chalk)
            .navigationTitle("Тренировки")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarLeading) {
                    // The app has no settings screen; «Данные» (export/import) lives here
                    // (plans/features/backup-sync, open question 1).
                    Button { isShowingData = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Данные")
                        .accessibilityIdentifier("workoutList.data")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { createWorkout() } label: { Image(systemName: "plus") }
                        .accessibilityIdentifier("workoutList.addWorkout")
                }
            }
            .overlay {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "Тренировок пока нет",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("Нажми «+» здесь или «Начать тренировку» внизу экрана")
                    )
                }
            }
            .navigationDestination(item: $newWorkout) { workout in
                WorkoutDetailView(workout: workout, restTimer: restTimer)
            }
            .sheet(isPresented: $isShowingData) {
                DataManagementView()
            }
        }
    }

    private func createWorkout() {
        let workout = Workout(sortIndex: Self.topSortIndex(among: workouts))
        context.insert(workout)
        newWorkout = workout
    }

    private func copyWorkout(_ workout: Workout) {
        _ = Workout.copy(of: workout, sortIndex: Self.topSortIndex(among: workouts), context: context)
        // The watch lists plans and can start them, so every change to the plan list is
        // a change it needs to see.
        WatchSessionManager.shared.refresh()
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            delete(workouts[index])
        }
    }

    private func delete(_ workout: Workout) {
        let wasActive = workout.isActive
        context.delete(workout)
        // `pushSnapshot(for: nil)` rather than `refresh()` for the active one: a fetch
        // still returns a deleted-but-unsaved row, so the store can't be asked yet.
        if wasActive {
            WatchSessionManager.shared.pushSnapshot(for: nil)
        } else {
            WatchSessionManager.shared.refresh()
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        Self.reorder(workouts, from: source, to: destination)
        WatchSessionManager.shared.refresh()
    }

    /// A brand-new/copied workout sorts above everything else without renumbering
    /// the rest of the list.
    static func topSortIndex(among workouts: [Workout]) -> Int {
        (workouts.map(\.sortIndex).min() ?? 0) - 1
    }

    /// `onMove` over a `@Query` result needs the new order written back to the
    /// model, or it reverts on the next query refresh. Renumbers the whole visible
    /// list to its current visual order first — otherwise, while every `sortIndex`
    /// is still the untouched default of 0, applying the move to indices alone
    /// would collapse the order. Pulled out as a static function over plain values
    /// so it's testable without a view hierarchy.
    static func reorder(_ workouts: [Workout], from source: IndexSet, to destination: Int) {
        for (index, workout) in workouts.enumerated() {
            workout.sortIndex = index
        }
        var reordered = workouts
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, workout) in reordered.enumerated() {
            workout.sortIndex = index
        }
    }
}

private struct WorkoutRow: View {
    let workout: Workout

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.name.isEmpty ? workout.date.formatted(date: .abbreviated, time: .shortened) : workout.name)
                    .font(.sans(16))
                    .foregroundStyle(.ink)
                Text("\(workout.orderedExercises.count) \(RussianPlural.form(workout.orderedExercises.count, "упражнение", "упражнения", "упражнений")) · \(workout.sets.count) \(RussianPlural.form(workout.sets.count, "подход", "подхода", "подходов"))")
                    .font(.mono(13))
                    .foregroundStyle(.steel)
            }
            Spacer()
            if workout.isActive {
                Text("Идёт").font(.mono(12)).foregroundStyle(.plateGreen)
            } else if workout.startedAt == nil {
                Text("План").font(.mono(12)).foregroundStyle(.steel)
            }
        }
        // Otherwise VoiceOver reads name, exercise/set counts, and status as three or
        // four separate elements instead of one row.
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let container = PreviewSupport.container()
    let context = container.mainContext
    let bench = Exercise(name: "Жим лёжа")
    let squat = Exercise(name: "Присед")
    context.insert(bench)
    context.insert(squat)

    let plan = Workout(name: "Завтра — грудь", sortIndex: 0)
    context.insert(plan)
    plan.addExercise(bench, weight: 60, reps: 8, context: context)

    let active = Workout(name: "", sortIndex: -1)
    context.insert(active)
    active.addExercise(squat, weight: 100, reps: 5, context: context)
    active.start()
    active.logSet(weight: 100, reps: 5, for: squat, context: context)

    let finished = Workout(name: "Спина", sortIndex: 1)
    context.insert(finished)
    finished.addExercise(bench, weight: 60, reps: 8, context: context)
    finished.start(now: Date(timeIntervalSinceNow: -3600))
    finished.logSet(weight: 60, reps: 8, for: bench, context: context)
    finished.finish()

    return WorkoutListView(restTimer: PreviewSupport.restTimer())
        .modelContainer(container)
}
