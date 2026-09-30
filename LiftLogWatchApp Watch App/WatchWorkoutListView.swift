import SwiftUI

/// Everything the watch can push. Value-based, so the whole stack lives in one `path`
/// the root owns — which is what lets it pop straight back to the list when the
/// workout ends, however deep the user is (see `WatchWorkoutListView.path`).
enum WatchRoute: Hashable {
    case workout
    /// By ID, not the summary itself: the plan drops out of `phone.plans` the moment
    /// it's started, and `PlanView` has to follow it into the running workout.
    case plan(UUID)
    case logSet(exerciseID: UUID)
}

/// Root screen: the workout that's running (if any) and the plans the phone sent, which
/// can be started from here — with or without the phone in range.
struct WatchWorkoutListView: View {
    let phone: PhoneSessionManager
    /// Reset to empty when the workout ends. Each screen dismissing itself didn't work:
    /// with the set-logging screen on top (e.g. its «План выполнен» → «Завершить»), the
    /// screens below dismissed and dropped their links, and the top one stayed put.
    @State private var path: [WatchRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
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
                                NavigationLink(value: WatchRoute.workout) {
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
                                    NavigationLink(value: WatchRoute.plan(plan.id)) {
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
            .navigationDestination(for: WatchRoute.self) { route in
                switch route {
                case .workout:
                    WorkoutSetsView(phone: phone)
                case .plan(let planID):
                    PlanView(phone: phone, planID: planID)
                case .logSet(let exerciseID):
                    LogSetView(phone: phone, exerciseID: exerciseID)
                }
            }
        }
        // Тренировка кончилась (здесь или на телефоне) — возвращаемся к списку, с какой
        // бы глубины ни смотрели. Показывать на её месте «Нет активной тренировки» или
        // экран плана, которого больше нет, нечестно.
        .onChange(of: phone.snapshot?.workoutID) { old, new in
            if old != nil, new == nil {
                path = []
            }
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
/// When it ends, the root pops the whole stack.
private struct PlanView: View {
    let phone: PhoneSessionManager
    let planID: UUID

    var body: some View {
        if phone.snapshot?.workoutID == planID {
            WorkoutSetsView(phone: phone)
        } else if let plan = phone.plans.first(where: { $0.id == planID }) {
            planList(plan)
        } else {
            // Удалён на телефоне, пока экран был открыт.
            ContentUnavailableView("Плана больше нет", systemImage: "figure.strengthtraining.traditional")
        }
    }

    private func planList(_ plan: WatchWorkoutSummary) -> some View {
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
