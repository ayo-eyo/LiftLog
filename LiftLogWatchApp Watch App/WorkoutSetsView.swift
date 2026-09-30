import SwiftUI
import WatchKit

/// The active workout: rest timer, exercises, and the way out of it. Reads the merged
/// state (`phone.snapshot`), so sets logged with no phone in range show up here right
/// away and stay put until the phone confirms them.
struct WorkoutSetsView: View {
    let phone: PhoneSessionManager
    @State private var isConfirmingFinish = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let snapshot = phone.snapshot, !snapshot.exercises.isEmpty {
                List {
                    // Condition on the Section's presence, not on its content — this
                    // way the ticking `TimelineView` only exists while actually
                    // resting, instead of running at 1Hz for as long as the workout
                    // screen is open, and the List's direct child is a stable
                    // Section/nothing rather than always-present-but-sometimes-empty.
                    if let restEndDate = snapshot.restEndDate {
                        Section {
                            TimelineView(.periodic(from: restEndDate, by: 1)) { timeline in
                                if restEndDate > timeline.date {
                                    restRow(remaining: restEndDate.timeIntervalSince(timeline.date), name: snapshot.restExerciseName)
                                }
                            }
                        }
                    }
                    ForEach(snapshot.exercises) { exercise in
                        NavigationLink {
                            LogSetView(phone: phone, exerciseID: exercise.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.name)
                                    Text(countLabel(for: exercise))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if exercise.isSetPlanFulfilled {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                    Section {
                        QueueStatusView(phone: phone)
                        Button("Завершить", role: .destructive) { isConfirmingFinish = true }
                            .font(.caption)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Нет активной тренировки",
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text("Начни её здесь или на телефоне")
                )
            }
        }
        .navigationTitle(title)
        .confirmationDialog("Завершить тренировку?", isPresented: $isConfirmingFinish, titleVisibility: .visible) {
            Button("Завершить", role: .destructive) { phone.finishWorkout() }
            Button("Отмена", role: .cancel) {}
        }
        // Тренировка кончилась (здесь или на телефоне) — возвращаемся к списку вместо
        // того, чтобы показывать «Нет активной тренировки» на месте только что
        // завершённой.
        .onChange(of: phone.snapshot?.workoutID) { old, new in
            if old != nil, new == nil {
                dismiss()
            }
        }
    }

    private var title: String {
        guard let snapshot = phone.snapshot else { return "Подходы" }
        return snapshot.name.isEmpty ? "Подходы" : snapshot.name
    }

    /// «2/4» when there's a plan (FR-1); a bare count for an exercise added
    /// mid-workout, which has nothing to be "of".
    private func countLabel(for exercise: WatchWorkoutSnapshot.ExerciseInfo) -> String {
        exercise.plannedSetCount > 0
            ? "\(exercise.setsLoggedCount)/\(exercise.plannedSetCount)"
            : "\(exercise.setsLoggedCount)"
    }

    private func restRow(remaining: TimeInterval, name: String?) -> some View {
        VStack(spacing: 4) {
            Text(name ?? "Отдых")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(clockString(remaining))
                .font(.title2.monospacedDigit())
            Button("Пропустить") { phone.skipRest() }
                .font(.caption2)
        }
        .frame(maxWidth: .infinity)
    }
}

/// One line about the offline queue — but only once it's actually stuck (see
/// `WatchSyncMerge.shouldWarnAboutQueue`). A queue that drains in a second is normal
/// operation, not news.
struct QueueStatusView: View {
    let phone: PhoneSessionManager

    var body: some View {
        // The `TimelineView` is scheduled on the exact moment the age threshold passes,
        // so the line can appear while the screen just sits there — and it only exists
        // while something is queued, instead of ticking for the whole workout.
        if let warningDate = WatchSyncMerge.queueWarningDate(phone.pending) {
            TimelineView(.periodic(from: warningDate, by: 60)) { _ in
                // The schedule is only here to force a re-render at the threshold; the
                // decision reads the real clock, since a schedule whose start is still
                // in the future can hand the body that future date on first render.
                if WatchSyncMerge.shouldWarnAboutQueue(phone.pending, now: Date()) {
                    label
                }
            }
        }
    }

    private var label: some View {
        Label(
            "\(phone.unsentCount) \(RussianPlural.form(phone.unsentCount, "запись", "записи", "записей")) не отправлено",
            systemImage: "arrow.triangle.2.circlepath"
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

func clockString(_ interval: TimeInterval) -> String {
    let seconds = max(0, Int(interval.rounded()))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}

private struct LogSetView: View {
    let phone: PhoneSessionManager
    /// `@State`, not `let` — FR-2's auto-advance swaps this in place instead of
    /// pushing a new screen, same reasoning as `WorkoutExerciseLogView.current` on the
    /// phone.
    @State private var exerciseID: UUID
    /// `Double`, not `Int` — `digitalCrownRotation` requires `BinaryFloatingPoint`;
    /// converted to `Int` only where it leaves this view (`phone.logSet`, the label).
    @State private var weight: Double = 20
    @State private var reps: Double = 10
    @State private var didLoadDefaults = false
    /// Shown instead of the input tiles once logging a set closes the last remaining
    /// exercise — see FR-2. Mirrors `WorkoutExerciseLogView.showPlanFulfilled`.
    @State private var showPlanFulfilled = false
    /// The weight of a set that was just a record; clears itself after a moment. Screen
    /// state, so it survives an auto-advance to the next exercise, like the phone's banner.
    @State private var recordBanner: Double?

    private enum Field: Hashable { case weight, reps }
    @FocusState private var field: Field?

    init(phone: PhoneSessionManager, exerciseID: UUID) {
        self.phone = phone
        _exerciseID = State(initialValue: exerciseID)
    }

    /// Always read through the merged snapshot rather than holding a copy: logging a set
    /// changes the next set's defaults, and this is where the new ones come from —
    /// whether the phone answered or the command is still sitting in the queue.
    private var exercise: WatchWorkoutSnapshot.ExerciseInfo? {
        phone.snapshot?.exercises.first { $0.id == exerciseID }
    }

    private var title: String {
        guard let exercise else { return "Подход" }
        guard exercise.plannedSetCount > 0 else { return exercise.name }
        let setNumber = max(exercise.setsLoggedCount, min(exercise.setsLoggedCount + 1, exercise.plannedSetCount))
        return "Подход \(setNumber) из \(exercise.plannedSetCount)"
    }

    var body: some View {
        VStack(spacing: 6) {
            if let recordBanner {
                recordBannerView(recordBanner)
            }
            if showPlanFulfilled {
                planFulfilledBanner
            } else {
                weightTile
                repsTile

                if let restEndDate = phone.snapshot?.restEndDate {
                    TimelineView(.periodic(from: restEndDate, by: 1)) { timeline in
                        if restEndDate > timeline.date {
                            Text(clockString(restEndDate.timeIntervalSince(timeline.date)))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                QueueStatusView(phone: phone)

                Button("Записать подход") { logSet() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(exercise == nil || reps <= 0)
            }
        }
        .padding(.horizontal, 6)
        .navigationTitle(title)
        .task(id: recordBanner) {
            guard recordBanner != nil else { return }
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return // replaced by a newer record, or the screen went away
            }
            withAnimation { recordBanner = nil }
        }
        .onAppear {
            // Once: after that the tiles hold whatever the user dialed in, and
            // `applyDefaults()` moves them on only when a set is actually logged.
            guard !didLoadDefaults else { return }
            didLoadDefaults = true
            applyDefaults()
        }
    }

    private static let weightStep: Double = 0.25
    private static let weightFormat: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(0...2))

    private var weightTile: some View {
        Text("\(weight.formatted(Self.weightFormat)) кг")
            .font(.title3.monospacedDigit())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(field == .weight ? Color.accentColor.opacity(0.2) : Color.clear, in: .rect(cornerRadius: 8))
            .focusable(true)
            .focused($field, equals: .weight)
            .digitalCrownRotation($weight, from: 0, through: 500, by: Self.weightStep, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
            // The crown drives `weight` continuously under the hood even with `by:` set —
            // rotation deltas accumulate float error, so left alone the binding drifts to
            // values like 20.000000000004 (which is what was rendering as fractions down
            // to the ten-thousandths). Snap back onto the step grid on every change.
            .onChange(of: weight) { _, newValue in
                weight = CrownStepping.snapped(newValue, step: Self.weightStep)
            }
            .onTapGesture { field = .weight }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Вес")
            .accessibilityValue("\(weight.formatted(Self.weightFormat)) килограмм")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: weight = min(500, weight + Self.weightStep)
                case .decrement: weight = max(0, weight - Self.weightStep)
                @unknown default: break
                }
            }
    }

    private var repsTile: some View {
        Text("× \(Int(reps.rounded()))")
            .font(.title3.monospacedDigit())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(field == .reps ? Color.accentColor.opacity(0.2) : Color.clear, in: .rect(cornerRadius: 8))
            .focusable(true)
            .focused($field, equals: .reps)
            .digitalCrownRotation($reps, from: 1, through: 50, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
            .onTapGesture { field = .reps }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Повторы")
            .accessibilityValue("\(Int(reps.rounded()))")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: reps = min(50, reps + 1)
                case .decrement: reps = max(1, reps - 1)
                @unknown default: break
                }
            }
    }

    private func recordBannerView(_ weight: Double) -> some View {
        Label("Рекорд · \(weight.formatted(Self.weightFormat)) кг", systemImage: "trophy.fill")
            .font(.caption)
            .foregroundStyle(.yellow)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .transition(.opacity)
            .onTapGesture { withAnimation { recordBanner = nil } }
            .accessibilityLabel("Новый рекорд, \(weight.formatted(Self.weightFormat)) килограмм")
    }

    private var planFulfilledBanner: some View {
        VStack(spacing: 8) {
            Text("План выполнен").font(.headline)
            Button("Завершить", role: .destructive) { phone.finishWorkout() }
                .font(.caption)
            Button("Продолжить") { withAnimation { showPlanFulfilled = false } }
                .font(.caption2)
        }
    }

    /// Logs the set, then applies FR-2 from the merged snapshot — `phone.logSet`
    /// enqueues synchronously, so `phone.snapshot` already reflects the new count
    /// right after the call, with no need to wait for the phone (technical-notes.md
    /// §2 "Навигация на часах").
    private func logSet() {
        guard let exercise, reps > 0 else { return }
        let wasFulfilled = exercise.isSetPlanFulfilled
        // Read before `phone.logSet`, like `wasFulfilled`: right after it the merged
        // snapshot's bar already includes this very set.
        let isRecord = exercise.isWeightRecord(weight)
        phone.logSet(exerciseID: exercise.id, exerciseName: exercise.name, weight: weight, reps: Int(reps.rounded()))
        if isRecord {
            withAnimation { recordBanner = weight }
            WKInterfaceDevice.current().play(.success)
        }

        // A queued `.finish` (or any other reason the workout just disappeared) makes
        // `phone.snapshot` nil — nothing to advance into.
        guard let snapshot = phone.snapshot,
              let updated = snapshot.exercises.first(where: { $0.id == exercise.id }),
              !wasFulfilled, updated.isSetPlanFulfilled else {
            applyDefaults()
            return
        }
        if let next = snapshot.nextUnfulfilledExercise(after: exercise.id) {
            exerciseID = next.id
            applyDefaults()
        } else {
            withAnimation { showPlanFulfilled = true }
        }
    }

    private func applyDefaults() {
        weight = exercise?.weight ?? 20
        reps = Double(exercise?.reps ?? 10)
        field = .weight
    }
}
