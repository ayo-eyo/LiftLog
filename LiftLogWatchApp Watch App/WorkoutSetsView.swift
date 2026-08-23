import SwiftUI

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
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name)
                                Text("\(exercise.setsLoggedCount) \(RussianPlural.form(exercise.setsLoggedCount, "подход", "подхода", "подходов"))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
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
    let exerciseID: UUID

    @State private var weight: Double = 0
    @State private var reps: Int = 0
    @State private var didLoadDefaults = false

    /// Always read through the merged snapshot rather than holding a copy: logging a set
    /// changes the next set's defaults, and this is where the new ones come from —
    /// whether the phone answered or the command is still sitting in the queue.
    private var exercise: WatchWorkoutSnapshot.ExerciseInfo? {
        phone.snapshot?.exercises.first { $0.id == exerciseID }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Stepper(value: $weight, in: 0...500, step: 0.25) {
                    Text("\(weight.formatted(.number)) кг")
                }
                .controlSize(.small)

                Stepper(value: $reps, in: 1...50) {
                    Text("× \(reps)")
                }
                .controlSize(.small)

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

                Button("Записать подход") {
                    guard let exercise, reps > 0 else { return }
                    phone.logSet(exerciseID: exercise.id, exerciseName: exercise.name, weight: weight, reps: reps)
                    applyDefaults()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(exercise == nil || reps <= 0)
            }
            .padding(.horizontal, 6)
        }
        .navigationTitle(exercise?.name ?? "Подход")
        .onAppear {
            // Once: after that the steppers hold whatever the user dialed in, and
            // `applyDefaults()` moves them on only when a set is actually logged.
            guard !didLoadDefaults else { return }
            didLoadDefaults = true
            applyDefaults()
        }
    }

    private func applyDefaults() {
        weight = exercise?.weight ?? 20
        reps = exercise?.reps ?? 10
    }
}
