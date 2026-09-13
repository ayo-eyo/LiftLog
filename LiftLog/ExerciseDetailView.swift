import SwiftUI
import SwiftData

/// An exercise's progress: the weight record, a per-session chart and the history grouped
/// by workout (plans/features/progress-analytics, FR-2). Read-only — sets are logged inside
/// a workout (decision 14); tapping one still opens `EditSetView`.
struct ExerciseDetailView: View {
    let exercise: Exercise

    @State private var editingSet: WorkoutSet?
    /// nil until the user picks one, so the defaults (decision 17, FR-2) keep applying —
    /// including the period's "fall back to «Всё»" rule as history grows.
    @State private var metric: ExerciseProgressMetric?
    @State private var period: ExerciseChartPeriod?

    var body: some View {
        // Derived on every render rather than cached: a few hundred sets sort in
        // microseconds, and reading each set here is also what redraws the screen after an
        // edit in `EditSetView`.
        let samples = ExerciseStats.samples(for: exercise)
        let sessions = ExerciseStats.sessions(samples)
        Group {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "Ещё нет подходов",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Запиши подходы в тренировке — здесь появится прогресс")
                )
            } else {
                content(samples: samples, sessions: sessions)
            }
        }
        .background(.chalk)
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingSet) { set in
            // Only an active workout has anything on the watch to refresh after the edit.
            EditSetView(set: set, workout: set.workout?.isActive == true ? set.workout : nil)
        }
    }

    private func content(samples: [SetSample], sessions: [ExerciseSession]) -> some View {
        let metrics = ExerciseStats.availableMetrics(samples)
        let shownMetric = metric.flatMap { metrics.contains($0) ? $0 : nil } ?? metrics[0]
        let shownPeriod = period ?? ExerciseStats.defaultPeriod(sessions, metric: shownMetric, now: .now, calendar: .current)
        let records = ExerciseStats.recordSetIDs(samples)

        return List {
            Section {
                ExerciseRecordTiles(samples: samples, sessions: sessions)
                ExerciseProgressChart(
                    sessions: sessions,
                    metrics: metrics,
                    metric: Binding(get: { shownMetric }, set: { metric = $0 }),
                    period: Binding(get: { shownPeriod }, set: { period = $0 })
                )
            }
            .listRowBackground(Color.chalk)
            .listRowSeparator(.hidden)

            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                Section {
                    ForEach(session.sets, id: \.id) { sample in
                        Button {
                            editingSet = exercise.sets.first { $0.persistentModelID == sample.id }
                        } label: {
                            SetRow(weight: sample.weight, reps: sample.reps, fontSize: 14, isRecord: records.contains(sample.id))
                        }
                        .listRowSeparatorTint(.hairline)
                        .listRowBackground(Color.chalk)
                    }
                } header: {
                    sessionHeader(session)
                        .accessibilityIdentifier("exerciseProgress.session.\(index)")
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func sessionHeader(_ session: ExerciseSession) -> some View {
        HStack {
            Text("\(ProgressFormat.day(session.date)) · \(title(of: session))")
                .font(.sans(13))
                .foregroundStyle(.ink)
            Spacer()
            if session.volume > 0 {
                Text(ProgressFormat.kg(session.volume))
                    .font(.mono(12))
                    .foregroundStyle(.steel)
            }
        }
    }

    private func title(of session: ExerciseSession) -> String {
        if session.isStandalone { return "Вне тренировки" }
        guard let name = session.workoutName, !name.isEmpty else { return "Тренировка" }
        return name
    }
}

#Preview {
    let container = PreviewSupport.container()
    let context = container.mainContext
    let bench = Exercise(name: "Жим лёжа", catalogID: "Barbell_Bench_Press_-_Medium_Grip")
    context.insert(bench)
    for (day, weights) in [(0, [60.0, 62.5]), (7, [62.5, 65]), (14, [65, 67.5])] {
        let date = Date.now.addingTimeInterval(Double(day - 14) * 86_400)
        let workout = Workout(date: date, name: "Грудь")
        context.insert(workout)
        workout.addExercise(bench, context: context)
        workout.start(now: date)
        for (index, weight) in weights.enumerated() {
            workout.logSet(weight: weight, reps: 6, for: bench, now: date.addingTimeInterval(Double(index + 1) * 120), context: context)
        }
        workout.finish(now: date.addingTimeInterval(1_800))
    }

    return NavigationStack {
        ExerciseDetailView(exercise: bench)
    }
    .modelContainer(container)
}
