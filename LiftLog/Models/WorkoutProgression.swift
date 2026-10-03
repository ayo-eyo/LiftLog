import Foundation
import SwiftData

/// The step a fulfilled weighted exercise gains and the rep ceiling a bodyweight one
/// climbs to (plans/features/progression, decisions 2–4).
nonisolated struct ProgressionSettings: Equatable, Sendable {
    var weightStep: Double
    var repLimit: Int

    static let standard = ProgressionSettings(weightStep: 2.5, repLimit: 20)
    static let weightStepRange: ClosedRange<Double> = 0.25...10
    static let weightStepIncrement: Double = 0.25
    /// The watch's reps crown tops out at the same 50.
    static let repLimitRange: ClosedRange<Int> = 1...50

    /// Back inside the allowed ranges and onto the 0.25 kg grid — a hand-edited backup or
    /// a value saved by an older build shouldn't produce a step the inputs can't show.
    func clamped() -> ProgressionSettings {
        let step = (weightStep / Self.weightStepIncrement).rounded() * Self.weightStepIncrement
        return ProgressionSettings(
            weightStep: min(max(step, Self.weightStepRange.lowerBound), Self.weightStepRange.upperBound),
            repLimit: min(max(repLimit, Self.repLimitRange.lowerBound), Self.repLimitRange.upperBound)
        )
    }
}

/// The app-wide progression settings, in `UserDefaults` (the screens read the same keys
/// through `@AppStorage`). `defaults` is the seam for tests. `nonisolated`: `load()` is a
/// default-parameter value (`BackupExporter.makeFile`), evaluated outside the main actor.
nonisolated enum ProgressionDefaults {
    static let weightStepKey = "progression.weightStep"
    static let repLimitKey = "progression.repLimit"

    static func load(_ defaults: UserDefaults = .standard) -> ProgressionSettings {
        let standard = ProgressionSettings.standard
        return ProgressionSettings(
            weightStep: defaults.object(forKey: weightStepKey) as? Double ?? standard.weightStep,
            repLimit: defaults.object(forKey: repLimitKey) as? Int ?? standard.repLimit
        ).clamped()
    }

    static func save(_ settings: ProgressionSettings, to defaults: UserDefaults = .standard) {
        let settings = settings.clamped()
        defaults.set(settings.weightStep, forKey: weightStepKey)
        defaults.set(settings.repLimit, forKey: repLimitKey)
    }
}

extension Exercise {
    /// `defaults` with this exercise's own overrides on top (decision 4).
    func progressionSettings(defaults: ProgressionSettings) -> ProgressionSettings {
        ProgressionSettings(
            weightStep: progressionWeightStep ?? defaults.weightStep,
            repLimit: progressionRepLimit ?? defaults.repLimit
        ).clamped()
    }
}

/// One planned position, as plain values — what the progression screen edits before
/// anything is written to the store.
struct ProgressionPosition: Equatable {
    var weight: Double?
    var reps: Int?
}

/// The progression verdict for one exercise of a finished workout.
struct ExerciseProgression: Identifiable {
    let exercise: Exercise
    /// This workout's plan for the exercise, in order.
    let current: [ProgressionPosition]
    /// The next plan by the rule — equal to `current` when nothing is gained.
    let suggested: [ProgressionPosition]
    let plannedVolume: Double
    let loggedVolume: Double
    let isBodyweight: Bool
    let isFulfilled: Bool

    var id: PersistentIdentifier { exercise.persistentModelID }
    var hasSuggestion: Bool { suggested != current }
}

/// The progression rule (plans/features/progression, FR-1). Nothing is stored: it's all
/// derived from the workout's plan and the sets logged in it.
enum WorkoutProgression {
    /// Every exercise of `workout`'s plan, in workout order — the ones the rule doesn't
    /// apply to too, since the next plan carries them over unchanged.
    static func progressions(for workout: Workout, settings: (Exercise) -> ProgressionSettings) -> [ExerciseProgression] {
        workout.groupedItems.map { group in
            let planned = group.items.map { ProgressionPosition(weight: $0.plannedWeight, reps: $0.plannedReps) }
            let logged = workout.setsFor(group.exercise).map { (weight: $0.weight, reps: $0.reps) }
            let verdict = progression(planned: planned, logged: logged, settings: settings(group.exercise))
            return ExerciseProgression(
                exercise: group.exercise,
                current: planned,
                suggested: verdict.suggested,
                plannedVolume: verdict.plannedVolume,
                loggedVolume: verdict.loggedVolume,
                isBodyweight: verdict.isBodyweight,
                isFulfilled: verdict.isFulfilled
            )
        }
    }

    struct Verdict: Equatable {
        var suggested: [ProgressionPosition]
        var plannedVolume: Double
        var loggedVolume: Double
        var isBodyweight: Bool
        var isFulfilled: Bool
    }

    /// The rule on plain values. Only positions with planned reps take part; the rest are
    /// carried over as they are. Volume is weight × reps, or just reps for a bodyweight
    /// exercise — one where no taking-part position has a weight above 0 (decision 2).
    /// Every logged set counts, the ones past the plan too (decision 1).
    static func progression(
        planned: [ProgressionPosition],
        logged: [(weight: Double, reps: Int)],
        settings: ProgressionSettings
    ) -> Verdict {
        let takingPart = planned.compactMap { position in position.reps.map { (weight: position.weight ?? 0, reps: $0) } }
        guard !takingPart.isEmpty else {
            return Verdict(suggested: planned, plannedVolume: 0, loggedVolume: 0, isBodyweight: false, isFulfilled: false)
        }

        let isBodyweight = takingPart.allSatisfy { $0.weight <= 0 }
        func volume(_ sets: [(weight: Double, reps: Int)]) -> Double {
            sets.reduce(0) { total, set in total + (isBodyweight ? Double(set.reps) : set.weight * Double(set.reps)) }
        }
        let plannedVolume = volume(takingPart)
        let loggedVolume = volume(logged)
        // Weights are on a 0.25 grid, so the sums are exact; the tolerance is only a guard.
        let isFulfilled = loggedVolume >= plannedVolume - 1e-9

        guard isFulfilled else {
            return Verdict(suggested: planned, plannedVolume: plannedVolume, loggedVolume: loggedVolume, isBodyweight: isBodyweight, isFulfilled: false)
        }
        let suggested = planned.map { position -> ProgressionPosition in
            guard let reps = position.reps else { return position }
            var next = position
            if isBodyweight {
                // Never lowered: a plan already past the limit stays where it is.
                next.reps = reps < settings.repLimit ? reps + 1 : reps
            } else if let weight = position.weight, weight > 0 {
                // Decision 3: weight grows, reps stay; a weightless position in a weighted
                // exercise is left alone.
                next.weight = weight + settings.weightStep
            }
            return next
        }
        return Verdict(suggested: suggested, plannedVolume: plannedVolume, loggedVolume: loggedVolume, isBodyweight: isBodyweight, isFulfilled: true)
    }
}
