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
    /// See `refreshingNow` — here only for the queue line.
    @State private var now = Date()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if phone.snapshot == nil && phone.plans.isEmpty {
                    // Именно «планов», а не «тренировок»: на часы уезжают только
                    // незапущенные тренировки и идущая, история остаётся на телефоне —
                    // иначе после завершения экран читается как «всё пропало».
                    ContentUnavailableView(
                        "No plans",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("Create a workout on the phone — it will show up here")
                    )
                } else {
                    List {
                        if let snapshot = phone.snapshot {
                            Section("In progress") {
                                NavigationLink(value: WatchRoute.workout) {
                                    row(
                                        title: snapshot.name.isEmpty ? String(localized: "Workout") : snapshot.name,
                                        subtitle: String(localized: "\(snapshot.exercises.count) exercises")
                                    )
                                }
                            }
                        }
                        if !phone.plans.isEmpty {
                            Section("Plans") {
                                ForEach(phone.plans) { plan in
                                    NavigationLink(value: WatchRoute.plan(plan.id)) {
                                        row(
                                            title: plan.name.isEmpty ? plan.date.formatted(date: .abbreviated, time: .omitted) : plan.name,
                                            subtitle: String(localized: "\(plan.exercises.count) exercises")
                                        )
                                    }
                                }
                            }
                        }
                        if WatchSyncMerge.shouldWarnAboutQueue(phone.pending, now: now) {
                            Section { QueueStatusLabel(phone: phone) }
                        }
                    }
                }
            }
            .navigationTitle("LiftLog")
            .refreshingNow($now, at: WatchSyncMerge.queueWarningDate(phone.pending))
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
        .alert("Couldn’t start", isPresented: startConflictBinding) {
            Button("Retry") { phone.retryAfterConflict() }
            Button("Cancel start", role: .destructive) { phone.cancelQueuedStart() }
        } message: {
            Text(conflictMessage)
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) { phone.lastError = nil }
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
            ? " " + String(localized: "If you cancel the start, \(sets) logged sets will be discarded.")
            : ""
        return String(localized: "Another workout is already running on the phone.") + tail
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
            ContentUnavailableView("This plan is gone", systemImage: "figure.strengthtraining.traditional")
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
            Button("Start") {
                phone.startWorkout(plan)
            }
            .buttonStyle(.borderedProminent)
            .disabled(plan.exercises.isEmpty || phone.snapshot != nil)
            // Without this the row draws its own rounded-rectangle background behind the
            // button, which reads as a stray slab around it.
            .listRowBackground(Color.clear)
        }
        .navigationTitle(plan.name.isEmpty ? String(localized: "Plan") : plan.name)
    }

    private func plannedDescription(_ sets: [WatchWorkoutSnapshot.PlannedSet]) -> String {
        let count = sets.count
        guard let first = sets.first, let weight = first.weight, let reps = first.reps else {
            return String(localized: "\(count) sets")
        }
        return String(localized: "\(count)×\(reps) · \(weight.formatted(.number)) kg")
    }
}
