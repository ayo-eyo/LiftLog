import SwiftUI
import SwiftData

struct WorkoutListView: View {
    let restTimer: RestTimer
    @Query(sort: [SortDescriptor(\Workout.sortIndex), SortDescriptor(\Workout.date, order: .reverse)])
    private var workouts: [Workout]
    @Environment(\.modelContext) private var context
    @State private var newWorkout: Workout?

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
                ToolbarItem(placement: .navigationBarLeading) { EditButton() }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { createWorkout() } label: { Image(systemName: "plus") }
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
        }
    }

    private func createWorkout() {
        let workout = Workout(sortIndex: Self.topSortIndex(among: workouts))
        context.insert(workout)
        newWorkout = workout
    }

    private func copyWorkout(_ workout: Workout) {
        _ = Workout.copy(of: workout, sortIndex: Self.topSortIndex(among: workouts), context: context)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            delete(workouts[index])
        }
    }

    private func delete(_ workout: Workout) {
        if workout.isActive {
            WatchSessionManager.shared.pushSnapshot(for: nil)
        }
        context.delete(workout)
    }

    private func move(from source: IndexSet, to destination: Int) {
        Self.reorder(workouts, from: source, to: destination)
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
    }
}
