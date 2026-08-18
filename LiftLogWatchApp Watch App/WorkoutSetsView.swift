import SwiftUI

struct WorkoutSetsView: View {
    let phone: PhoneSessionManager

    var body: some View {
        NavigationStack {
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
                                LogSetView(phone: phone, exercise: exercise)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.name)
                                    Text("\(exercise.setsLoggedCount) \(RussianPlural.form(exercise.setsLoggedCount, "подход", "подхода", "подходов"))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Нет активной тренировки",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("Начни тренировку на телефоне")
                    )
                }
            }
            .navigationTitle("Подходы")
        }
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

private func clockString(_ interval: TimeInterval) -> String {
    let seconds = max(0, Int(interval.rounded()))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}

private struct LogSetView: View {
    let phone: PhoneSessionManager
    let exercise: WatchWorkoutSnapshot.ExerciseInfo

    @State private var weight: Double
    @State private var reps: Int
    @State private var isSaving = false
    @State private var statusText: String?
    @Environment(\.dismiss) private var dismiss

    init(phone: PhoneSessionManager, exercise: WatchWorkoutSnapshot.ExerciseInfo) {
        self.phone = phone
        self.exercise = exercise
        _weight = State(initialValue: exercise.weight ?? 20)
        _reps = State(initialValue: exercise.reps ?? 10)
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

                if let statusText {
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button {
                    guard weight > 0, reps > 0 else { return }
                    isSaving = true
                    statusText = nil
                    phone.logSet(exerciseID: exercise.id, exerciseName: exercise.name, weight: weight, reps: reps) { result in
                        DispatchQueue.main.async {
                            isSaving = false
                            switch result {
                            case .confirmed(let info):
                                weight = info.weight ?? weight
                                reps = info.reps ?? reps
                            case .queued:
                                statusText = "Поставлено в очередь — отправится, когда телефон будет рядом"
                            case .failed:
                                statusText = "Не удалось отправить"
                            }
                        }
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Записать подход")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isSaving || weight <= 0 || reps <= 0)
            }
            .padding(.horizontal, 6)
        }
        .navigationTitle(exercise.name)
    }
}
