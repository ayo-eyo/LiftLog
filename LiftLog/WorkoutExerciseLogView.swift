import SwiftUI
import SwiftData

struct WorkoutExerciseLogView: View {
    let workout: Workout
    let restTimer: RestTimer
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// The exercise this screen shows. `@State`, not `let` — FR-2's auto-advance
    /// swaps it in place instead of pushing a new screen, so «Назад» always lands on
    /// the exercise list rather than walking back through every exercise visited
    /// (`WorkoutDetailView`'s own comment on `copyWorkout` has the story on why
    /// pushing the same screen type from itself is a bad idea here).
    @State private var current: Exercise
    @State private var weight: Double?
    @State private var reps: Int?
    @State private var editingSet: WorkoutSet?
    /// Shown instead of the input block once logging a set closes the last remaining
    /// exercise — see FR-2. Never set automatically on appearance, only as the result
    /// of `logSet()`, so revisiting an already-fulfilled exercise doesn't reopen it.
    @State private var showPlanFulfilled = false
    /// Set by `logSet()` when the set just logged beat the weight record; clears itself
    /// after a few seconds or on tap. Screen state, not tied to `current`, so it survives
    /// an auto-advance and shows on the next exercise (plans/features/progress-analytics, FR-3).
    @State private var recordBanner: WeightRecordBreak?

    init(workout: Workout, exercise: Exercise, restTimer: RestTimer) {
        self.workout = workout
        self.restTimer = restTimer
        _current = State(initialValue: exercise)
    }

    /// Prefill priority: plan default for the next planned position → last set logged
    /// in this workout → last set ever logged for this exercise → empty. A `static`
    /// function (not `init` state) so the priority order is testable without
    /// instantiating the view, and so `.task(id:)` can call it again whenever
    /// `current` changes.
    static func prefill(workout: Workout, exercise: Exercise) -> (weight: Double?, reps: Int?) {
        let sessionLast = workout.setsFor(exercise).last
        let allTimeLast = exercise.sets.sorted { ($0.createdAt, $0.order) < ($1.createdAt, $1.order) }.last
        let plannedWeight = workout.defaultWeight(for: exercise)
        let plannedReps = workout.defaultReps(for: exercise)

        return (
            plannedWeight ?? sessionLast?.weight ?? allTimeLast?.weight,
            plannedReps ?? sessionLast?.reps ?? allTimeLast?.reps
        )
    }

    private var weightBinding: Binding<Double> {
        Binding(get: { weight ?? 0 }, set: { weight = $0 })
    }

    private var repsBinding: Binding<Int> {
        Binding(get: { reps ?? 0 }, set: { reps = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            MuscleMapHero(primaryMuscles: current.primaryMuscles, secondaryMuscles: current.secondaryMuscles, height: 180)
            // The banner takes the progress bar's slot (decision 15). It sits outside the
            // `showPlanFulfilled` branch, which hides that slot — otherwise a record set on
            // the plan's very last set would never be seen.
            if let recordBanner {
                recordBannerView(recordBanner)
            }
            if showPlanFulfilled {
                planFulfilledBanner
            } else {
                let planned = workout.plannedSetCount(for: current)
                if recordBanner == nil, planned > 0 {
                    SetProgressView(logged: workout.loggedSetCount(for: current), planned: planned)
                        .padding(.horizontal)
                }
                lastTimeRow
                inputBlock
            }
            if let endDate = restTimer.endDate {
                TimelineView(.periodic(from: endDate, by: 1)) { timeline in
                    if restTimer.isResting(at: timeline.date) {
                        restBlock
                    }
                }
            }
            historyList
        }
        .background(.chalk)
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingSet) { set in
            EditSetView(set: set, workout: workout)
        }
        .task(id: current.persistentModelID) {
            let prefill = Self.prefill(workout: workout, exercise: current)
            weight = prefill.weight
            reps = prefill.reps
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    // A different screen type, so this doesn't run into the "don't push
                    // this screen from itself" problem described on `current`.
                    ExerciseDetailView(exercise: current)
                } label: {
                    Image(systemName: "chart.xyaxis.line")
                }
                .accessibilityLabel("История")
                .accessibilityIdentifier("exerciseLog.history")
            }
        }
        .sensoryFeedback(.success, trigger: recordBanner) { _, new in new != nil }
        .task(id: recordBanner) {
            guard recordBanner != nil else { return }
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return // a newer record replaced this one, or the screen went away
            }
            withAnimation { recordBanner = nil }
        }
    }

    private var inputBlock: some View {
        VStack(spacing: 12) {
            WeightInputRow(weight: $weight, stepper: weightBinding)
            RepsInputRow(reps: $reps, stepper: repsBinding)
            Button("Добавить подход") {
                logSet()
            }
            .font(.sans(15))
            .buttonStyle(.borderedProminent)
            .tint(.plateBlue)
            .disabled(weight == nil || reps == nil || (reps ?? 0) <= 0)
            .accessibilityIdentifier("exerciseLog.addSet")
        }
        .padding()
    }

    /// Logs the set, then applies FR-2: stay and roll defaults forward, jump to the
    /// next unfulfilled exercise, or show the "plan fulfilled" banner. `wasFulfilled`
    /// is read before `workout.logSet` — see `WorkoutFlow.advance`'s doc comment for
    /// why the ordering matters.
    private func logSet() {
        guard let w = weight, let r = reps, w >= 0, r > 0 else { return }
        let wasFulfilled = workout.isSetPlanFulfilled(for: current)
        let newSet = workout.logSet(weight: w, reps: r, for: current, context: context)
        // Checked against `current` before `WorkoutFlow.advance` below can swap it.
        if let record = ExerciseStats.recordBeaten(by: newSet.persistentModelID, in: ExerciseStats.samples(for: current)) {
            withAnimation { recordBanner = record }
            AccessibilityNotification.Announcement("Новый рекорд, \(ProgressFormat.kg(record.weight))").post()
        }
        restTimer.start(duration: RestTimer.defaultDuration, exerciseName: current.name)
        WatchSessionManager.shared.pushSnapshot(for: workout)

        switch WorkoutFlow.advance(after: current, wasFulfilled: wasFulfilled, in: workout) {
        case .stay:
            if let nextWeight = workout.defaultWeight(for: current) {
                weight = nextWeight
            }
            if let nextReps = workout.defaultReps(for: current) {
                reps = nextReps
            }
        case .next(let nextExercise):
            withAnimation {
                current = nextExercise
            }
        case .planFulfilled:
            withAnimation {
                showPlanFulfilled = true
            }
        }
    }

    private var planFulfilledBanner: some View {
        VStack(spacing: 12) {
            Text("План выполнен")
                .font(.display(20))
                .foregroundStyle(.ink)
            Text("Все запланированные подходы записаны")
                .font(.sans(13))
                .foregroundStyle(.steel)
                .multilineTextAlignment(.center)
            Button("Завершить тренировку") {
                // Pops back to `WorkoutDetailView`, which then shows the completed
                // summary — that screen's own toolbar ("Закрыть") is the way out of
                // the `fullScreenCover` from there. A more direct route (closing the
                // cover straight from here) was tried three different ways — a
                // passed-down `dismiss` closure, a reactive `.onChange`/`.onAppear` on
                // `WorkoutDetailView`, and a `NotificationCenter` post observed by
                // `RootTabView` — and none of them reliably closed the cover from two
                // navigation levels down in this environment; the closure version even
                // reproducibly hung the app for ~60s (confirmed with a clean
                // `DerivedData`, twice). A plain local `dismiss()` is the one thing
                // that's proven to work.
                Workout.complete(workout, restTimer: restTimer, context: context)
                dismiss()
            }
            .font(.sans(15))
            .buttonStyle(.borderedProminent)
            .tint(.plateBlue)
            Button("Продолжить") {
                withAnimation { showPlanFulfilled = false }
            }
            .font(.sans(14))
            .foregroundStyle(.steel)
        }
        .padding()
        .accessibilityIdentifier("exerciseLog.planFulfilled")
    }

    private func recordBannerView(_ record: WeightRecordBreak) -> some View {
        Button {
            withAnimation { recordBanner = nil }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.plateRed)
                Text("Новый рекорд · \(ProgressFormat.kg(record.weight))")
                    .font(.sans(13))
                    .foregroundStyle(.ink)
                Spacer()
                Text("было \(ProgressFormat.kg(record.previous))")
                    .font(.sans(11))
                    .foregroundStyle(.steel)
            }
            // Roughly `SetProgressView`'s height, so swapping one for the other doesn't
            // shove the inputs below up and down.
            .frame(minHeight: 28)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .transition(.opacity)
        .accessibilityIdentifier("exerciseLog.recordBanner")
    }

    /// «Прошлый раз» — the exercise's latest session before this workout; tap for the
    /// full progress screen. Nothing at all when there's no earlier session.
    @ViewBuilder
    private var lastTimeRow: some View {
        if let last = ExerciseStats.lastSession(ExerciseStats.samples(for: current), before: workout) {
            NavigationLink {
                ExerciseDetailView(exercise: current)
            } label: {
                Text("Прошлый раз, \(ProgressFormat.day(last.date)): \(Self.setsSummary(last.sets))")
                    .font(.mono(12))
                    .foregroundStyle(.steel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.top, 8)
            .accessibilityIdentifier("exerciseLog.lastTime")
        }
    }

    /// «60×8 · 60×8 · 57,5×7».
    static func setsSummary(_ sets: [SetSample]) -> String {
        sets.map { "\($0.weight.formatted(.number))×\($0.reps)" }.joined(separator: " · ")
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
        let records = ExerciseStats.recordSetIDs(ExerciseStats.samples(for: current))
        return List {
            ForEach(workout.setsFor(current)) { set in
                Button {
                    editingSet = set
                } label: {
                    SetRow(weight: set.weight, reps: set.reps, isRecord: records.contains(set.persistentModelID))
                }
                .listRowSeparatorTint(.hairline)
                .listRowBackground(Color.chalk)
            }
        }
        .scrollContentBackground(.hidden)
        .background(.chalk)
    }
}

#Preview {
    let container = PreviewSupport.container()
    let context = container.mainContext
    let bench = Exercise(name: "Жим лёжа", catalogID: "Barbell_Bench_Press_-_Medium_Grip")
    context.insert(bench)
    let workout = Workout(name: "Грудь")
    context.insert(workout)
    workout.addExercise(bench, weight: 60, reps: 8, context: context)
    workout.start()
    workout.logSet(weight: 60, reps: 8, for: bench, context: context)

    return NavigationStack {
        WorkoutExerciseLogView(workout: workout, exercise: bench, restTimer: PreviewSupport.restTimer())
    }
    .modelContainer(container)
}
