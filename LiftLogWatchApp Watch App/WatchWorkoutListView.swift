import SwiftUI

/// Root screen: the workout that's running (if any) and the plans the phone sent, which
/// can be started from here — with or without the phone in range.
struct WatchWorkoutListView: View {
    let phone: PhoneSessionManager

    var body: some View {
        NavigationStack {
            Group {
                if phone.snapshot == nil && phone.plans.isEmpty {
                    // Именно «планов», а не «тренировок»: на часы уезжают только
                    // незапущенные тренировки и идущая, история остаётся на телефоне —
                    // иначе после завершения экран читается как «всё пропало».
                    ContentUnavailableView(
                        "Планов нет",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("Создай тренировку на телефоне — она появится здесь")
                    )
                } else {
                    List {
                        if let snapshot = phone.snapshot {
                            Section("Идёт") {
                                NavigationLink {
                                    WorkoutSetsView(phone: phone)
                                } label: {
                                    row(
                                        title: snapshot.name.isEmpty ? "Тренировка" : snapshot.name,
                                        subtitle: "\(snapshot.exercises.count) \(RussianPlural.form(snapshot.exercises.count, "упражнение", "упражнения", "упражнений"))"
                                    )
                                }
                            }
                        }
                        if !phone.plans.isEmpty {
                            Section("Планы") {
                                ForEach(phone.plans) { plan in
                                    NavigationLink {
                                        PlanView(phone: phone, plan: plan)
                                    } label: {
                                        row(
                                            title: plan.name.isEmpty ? plan.date.formatted(date: .abbreviated, time: .omitted) : plan.name,
                                            subtitle: "\(plan.exercises.count) \(RussianPlural.form(plan.exercises.count, "упражнение", "упражнения", "упражнений"))"
                                        )
                                    }
                                }
                            }
                        }
                        Section { QueueStatusView(phone: phone) }
                    }
                }
            }
            .navigationTitle("LiftLog")
        }
        .alert("Не удалось начать", isPresented: startConflictBinding) {
            Button("Повторить") { phone.retryAfterConflict() }
            Button("Отменить старт", role: .destructive) { phone.cancelQueuedStart() }
        } message: {
            Text(conflictMessage)
        }
        .alert("Ошибка", isPresented: errorBinding) {
            Button("Ок", role: .cancel) { phone.lastError = nil }
        } message: {
            Text(phone.lastError ?? "")
        }
    }

    private func row(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// The queue isn't thrown away on a conflict, so the alert is the only place it can
    /// be resolved — read-only binding, dismissal goes through one of the two buttons.
    private var startConflictBinding: Binding<Bool> {
        Binding(get: { phone.startConflict != nil }, set: { _ in })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { phone.lastError != nil }, set: { if !$0 { phone.lastError = nil } })
    }

    private var conflictMessage: String {
        let sets = phone.queuedSetCountForConflict
        let tail = sets > 0
            ? " Если отменить старт, \(sets) \(RussianPlural.form(sets, "записанный подход", "записанных подхода", "записанных подходов")) будет отброшено."
            : ""
        return "На телефоне уже идёт другая тренировка." + tail
    }
}

/// A plan: what's in it, and the button that starts it. Starting works offline — the
/// command waits in the queue and the workout shows as running in the meantime.
///
/// Once it's running, this screen *becomes* the workout instead of popping back to the
/// list: the user asked to start this workout, so that's where they should end up.
private struct PlanView: View {
    let phone: PhoneSessionManager
    let plan: WatchWorkoutSummary
    @Environment(\.dismiss) private var dismiss
    @State private var didStart = false

    private var isRunning: Bool { phone.snapshot?.workoutID == plan.id }

    var body: some View {
        Group {
            if isRunning {
                WorkoutSetsView(phone: phone)
            } else {
                planList
            }
        }
        .onChange(of: isRunning) { _, running in
            if running {
                didStart = true
            } else if didStart {
                // Тренировка завершена — возвращаемся к списку. Показывать снова экран
                // плана нечестно: этого плана больше нет, начать его повторно нельзя.
                dismiss()
            }
        }
    }

    private var planList: some View {
        List {
            ForEach(plan.exercises) { exercise in
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                    if !exercise.plannedSets.isEmpty {
                        Text(plannedDescription(exercise.plannedSets))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button("Начать") {
                phone.startWorkout(plan)
            }
            .buttonStyle(.borderedProminent)
            .disabled(plan.exercises.isEmpty || phone.snapshot != nil)
            // Without this the row draws its own rounded-rectangle background behind the
            // button, which reads as a stray slab around it.
            .listRowBackground(Color.clear)
        }
        .navigationTitle(plan.name.isEmpty ? "План" : plan.name)
    }

    private func plannedDescription(_ sets: [WatchWorkoutSnapshot.PlannedSet]) -> String {
        let count = sets.count
        guard let first = sets.first, let weight = first.weight, let reps = first.reps else {
            return "\(count) \(RussianPlural.form(count, "подход", "подхода", "подходов"))"
        }
        return "\(count)×\(reps) · \(weight.formatted(.number)) кг"
    }
}
