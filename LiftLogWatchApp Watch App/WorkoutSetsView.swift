import SwiftUI
import WatchKit

/// The active workout: rest timer, exercises, and the way out of it. Reads the merged
/// state (`phone.snapshot`), so sets logged with no phone in range show up here right
/// away and stay put until the phone confirms them.
struct WorkoutSetsView: View {
    let phone: PhoneSessionManager
    @State private var isConfirmingFinish = false
    /// Moved forward by `refreshingNow` exactly when the rest ends or the queue turns
    /// stale — see there.
    @State private var now = Date()

    var body: some View {
        Group {
            if let snapshot = phone.snapshot, !snapshot.exercises.isEmpty {
                List {
                    // Condition on the Section's presence, not on its content — this
                    // way the ticking `TimelineView` only exists while actually
                    // resting, instead of running at 1Hz for as long as the workout
                    // screen is open. And against `now`, not just `restEndDate != nil`:
                    // the snapshot keeps the end date after the rest is over, and a row
                    // whose content has gone empty still draws as a blank slab.
                    if let restEndDate = snapshot.restEndDate, restEndDate > now {
                        Section {
                            TimelineView(.periodic(from: restEndDate, by: 1)) { timeline in
                                if restEndDate > timeline.date {
                                    restRow(remaining: restEndDate.timeIntervalSince(timeline.date), name: snapshot.restExerciseName)
                                }
                            }
                        }
                    }
                    ForEach(snapshot.exercises) { exercise in
                        NavigationLink(value: WatchRoute.logSet(exerciseID: exercise.id)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.name)
                                    Text(countLabel(for: exercise))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    // This workout's plan, set by set. Last time belongs on the
                                    // set screen, next to the plan's numbers in the tiles
                                    // (plans/features/last-session, FR-3).
                                    if let plan = planLabel(for: exercise) {
                                        Text(plan)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .truncationMode(.tail)
                                    }
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
                        if WatchSyncMerge.shouldWarnAboutQueue(phone.pending, now: now) {
                            QueueStatusLabel(phone: phone)
                        }
                        Button("Finish", role: .destructive) { isConfirmingFinish = true }
                            .font(.caption)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No active workout",
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text("Start one here or on the phone")
                )
            }
        }
        .navigationTitle(title)
        .refreshingNow($now, at: phone.snapshot?.restEndDate)
        .refreshingNow($now, at: WatchSyncMerge.queueWarningDate(phone.pending))
        .confirmationDialog("Finish the workout?", isPresented: $isConfirmingFinish, titleVisibility: .visible) {
            Button("Finish", role: .destructive) { phone.finishWorkout() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var title: String {
        guard let snapshot = phone.snapshot else { return String(localized: "Sets") }
        return snapshot.name.isEmpty ? String(localized: "Sets") : snapshot.name
    }

    /// «2/4» when there's a plan (FR-1); a bare count for an exercise added
    /// mid-workout, which has nothing to be "of".
    private func countLabel(for exercise: WatchWorkoutSnapshot.ExerciseInfo) -> String {
        exercise.plannedSetCount > 0
            ? "\(exercise.setsLoggedCount)/\(exercise.plannedSetCount)"
            : "\(exercise.setsLoggedCount)"
    }

    /// «20×10 · 20×10 · 25×8»; nil with no planned numbers at all.
    private func planLabel(for exercise: WatchWorkoutSnapshot.ExerciseInfo) -> String? {
        let sets = exercise.plannedSets.compactMap { set -> String? in
            switch (set.weight, set.reps) {
            case let (weight?, reps?): "\(weight.formatted(.number))×\(reps)"
            case let (nil, reps?): "×\(reps)"
            case let (weight?, nil): String(localized: "\(weight.formatted(.number)) kg")
            case (nil, nil): nil
            }
        }
        return sets.isEmpty ? nil : sets.joined(separator: " · ")
    }

    private func restRow(remaining: TimeInterval, name: String?) -> some View {
        VStack(spacing: 4) {
            Text(name ?? String(localized: "Rest"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(clockString(remaining))
                .font(.title2.monospacedDigit())
            Button("Skip") { phone.skipRest() }
                .font(.caption2)
        }
        .frame(maxWidth: .infinity)
    }
}

/// One line about the offline queue — shown only once it's actually stuck (see
/// `WatchSyncMerge.shouldWarnAboutQueue`); a queue that drains in a second is normal
/// operation, not news. The caller decides whether it's shown, not this view: inside a
/// `List`, a view that renders nothing still takes a row and draws as a blank slab.
struct QueueStatusLabel: View {
    let phone: PhoneSessionManager

    var body: some View {
        Label(
            "\(phone.unsentCount) entries not sent",
            systemImage: "arrow.triangle.2.circlepath"
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

extension View {
    /// Sets `now` to the current time once `date` arrives (and whenever `date` changes),
    /// so something whose *presence* depends on the clock — a finished rest, a queue that
    /// has aged into a warning — appears or goes away on time without a `TimelineView`
    /// re-rendering the whole screen every second.
    func refreshingNow(_ now: Binding<Date>, at date: Date?) -> some View {
        task(id: date) {
            now.wrappedValue = Date()
            guard let date else { return }
            let delay = date.timeIntervalSinceNow
            guard delay > 0 else { return }
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return // `date` changed or the screen went away
            }
            now.wrappedValue = Date()
        }
    }
}

extension View {
    /// Weight/reps tile: always on a fill, so both tap targets show where they end, and the
    /// one the crown turns gets a green ring — the system's own color for crown focus. Not
    /// the accent color: the watch app doesn't set one, and the default read as plain gray.
    func inputTile(isFocused: Bool) -> some View {
        background(Color.white.opacity(isFocused ? 0.18 : 0.1), in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.green, lineWidth: isFocused ? 2 : 0)
            }
    }
}

/// «57,5×7» — same shape as the phone's «Прошлый раз».
func setLabel(_ set: WatchWorkoutSnapshot.LoggedSet) -> String {
    "\(set.weight.formatted(.number))×\(set.reps)"
}

func clockString(_ interval: TimeInterval) -> String {
    let seconds = max(0, Int(interval.rounded()))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}

struct LogSetView: View {
    let phone: PhoneSessionManager
    /// `@State`, not `let` — FR-2's auto-advance swaps this in place instead of
    /// pushing a new screen, same reasoning as `WorkoutExerciseLogView.current` on the
    /// phone.
    @State private var exerciseID: UUID
    /// `Double`, not `Int` — `digitalCrownRotation` requires `BinaryFloatingPoint`;
    /// converted to `Int` only where it leaves this view (`phone.logSet`, the label).
    /// The weight crown turns `weightCrown`, counted in steps, not kilograms — see
    /// `CrownStepping.weightCrownStride`; `weight` is read and set through it.
    @State private var weightCrown: Double = CrownStepping.crownValue(forWeight: 20)
    @State private var reps: Double = 10
    @State private var didLoadDefaults = false
    /// Shown instead of the input tiles once logging a set closes the last remaining
    /// exercise — see FR-2. Mirrors `WorkoutExerciseLogView.showPlanFulfilled`.
    @State private var showPlanFulfilled = false
    /// The weight of a set that was just a record; clears itself after a moment. Screen
    /// state, so it survives an auto-advance to the next exercise, like the phone's banner.
    @State private var recordBanner: Double?
    /// See `refreshingNow` — here only for the queue line.
    @State private var now = Date()

    private var weight: Double {
        get { CrownStepping.weight(forCrownValue: weightCrown) }
        nonmutating set { weightCrown = CrownStepping.crownValue(forWeight: newValue) }
    }

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

    /// The exercise's name — without it, remembering what the set is *of* meant going back
    /// to the list. The set count is on the button instead (`logButtonTitle`): a line of its
    /// own above the tiles ran into the title once the rest timer was on screen too.
    private var title: String {
        guard let name = exercise?.name, !name.isEmpty else { return String(localized: "Set") }
        return name
    }

    /// «Записать 1 из 3» — the count sits on the action that logs that very set. Past the
    /// plan (after «Продолжить») or with no plan there's nothing to be "of", and a clamped
    /// «3 из 3» on the fourth set would be a lie.
    private var logButtonTitle: String {
        guard let exercise, exercise.setsLoggedCount < exercise.plannedSetCount else { return String(localized: "Log set") }
        return String(localized: "Log \(exercise.setsLoggedCount + 1) of \(exercise.plannedSetCount)")
    }

    var body: some View {
        VStack(spacing: 6) {
            if let recordBanner {
                recordBannerView(recordBanner)
            }
            if showPlanFulfilled {
                planFulfilledBanner
            } else {
                // Side by side, not stacked: the watch has room for exactly as many lines as
                // this screen had before «Прошлый раз», and one more slid under the title.
                HStack(spacing: 4) {
                    weightTile
                    repsTile
                }
                // The same set from last time — set 2 shows last time's second set — right
                // under the numbers being dialed in, which is what it gets compared with.
                if let last = exercise?.lastSessionSetForNext {
                    Text("Last time: \(setLabel(last))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let restEndDate = phone.snapshot?.restEndDate {
                    TimelineView(.periodic(from: restEndDate, by: 1)) { timeline in
                        if restEndDate > timeline.date {
                            Text(clockString(restEndDate.timeIntervalSince(timeline.date)))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if WatchSyncMerge.shouldWarnAboutQueue(phone.pending, now: now) {
                    QueueStatusLabel(phone: phone)
                }

                Button(logButtonTitle) { logSet() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    // «Записать 10 из 12» on a 40 mm watch: shrink rather than wrap.
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .disabled(exercise == nil || reps <= 0)
            }
        }
        .padding(.horizontal, 6)
        .navigationTitle(title)
        .refreshingNow($now, at: WatchSyncMerge.queueWarningDate(phone.pending))
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

    private static let weightStep = CrownStepping.weightStep
    private static let maxWeight = CrownStepping.maxWeight
    private static let weightFormat: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(0...2))

    private var weightTile: some View {
        Text("\(weight.formatted(Self.weightFormat)) kg")
            .font(.title3.monospacedDigit())
            // Half the width now: «102,25 кг» shrinks rather than wraps.
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .inputTile(isFocused: field == .weight)
            .focusable(true)
            .focused($field, equals: .weight)
            // Same sensitivity and stride as reps: one detent is one 0.25 kg step. Bound to
            // kilograms with `by: 0.25` instead, a small turn ran through several steps.
            .digitalCrownRotation(
                $weightCrown,
                from: 0,
                through: CrownStepping.crownValue(forWeight: Self.maxWeight),
                by: CrownStepping.weightCrownStride,
                sensitivity: .low,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
            // The crown drives the value continuously under the hood even with `by:` set —
            // rotation deltas accumulate float error, so left alone the binding drifts
            // between detents. Snap back onto the grid on every change.
            .onChange(of: weightCrown) { _, newValue in
                weightCrown = CrownStepping.snapped(newValue, step: CrownStepping.weightCrownStride)
            }
            .onTapGesture { field = .weight }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weight")
            .accessibilityValue("\(weight.formatted(Self.weightFormat)) kilograms")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: weight = min(Self.maxWeight, weight + Self.weightStep)
                case .decrement: weight = max(0, weight - Self.weightStep)
                @unknown default: break
                }
            }
    }

    private var repsTile: some View {
        Text("× \(Int(reps.rounded()))")
            .font(.title3.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .inputTile(isFocused: field == .reps)
            .focusable(true)
            .focused($field, equals: .reps)
            .digitalCrownRotation($reps, from: 1, through: 50, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
            .onTapGesture { field = .reps }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Reps")
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
        Label("Record · \(weight.formatted(Self.weightFormat)) kg", systemImage: "trophy.fill")
            .font(.caption)
            .foregroundStyle(.yellow)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .transition(.opacity)
            .onTapGesture { withAnimation { recordBanner = nil } }
            .accessibilityLabel("New record, \(weight.formatted(Self.weightFormat)) kilograms")
    }

    private var planFulfilledBanner: some View {
        VStack(spacing: 8) {
            Text("Plan complete").font(.headline)
            Button("Finish", role: .destructive) { phone.finishWorkout() }
                .font(.caption)
            Button("Continue") { withAnimation { showPlanFulfilled = false } }
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
