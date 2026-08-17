import SwiftUI

struct CatalogExerciseDetailView: View {
    let exercise: CatalogExercise

    /// `instructions` is a plain `[String]`, so `ForEach` needs stable identity of
    /// its own rather than `id: \.offset` — position never actually changes here
    /// (the array is fixed for the screen's lifetime), but this stays correct even
    /// if it ever didn't, and avoids the flagged `.offset`-as-identity anti-pattern.
    private struct Step: Identifiable {
        let number: Int
        let text: String
        var id: Int { number }
    }

    private var steps: [Step] {
        exercise.instructions.enumerated().map { Step(number: $0.offset + 1, text: $0.element) }
    }

    var body: some View {
        VStack(spacing: 0) {
            MuscleMapHero(primaryMuscles: exercise.primaryMuscles, secondaryMuscles: exercise.secondaryMuscles)
            List {
                Section("Мышцы") {
                    LabeledContent("Основные", value: exercise.primaryMuscles.joined(separator: ", ").capitalized)
                    if !exercise.secondaryMuscles.isEmpty {
                        LabeledContent("Вспомогательные", value: exercise.secondaryMuscles.joined(separator: ", ").capitalized)
                    }
                }
                Section("Параметры") {
                    if let equipment = exercise.equipment {
                        LabeledContent("Оборудование", value: equipment.capitalized)
                    }
                    if let level = exercise.level {
                        LabeledContent("Уровень", value: level.capitalized)
                    }
                    if let force = exercise.force {
                        LabeledContent("Усилие", value: force.capitalized)
                    }
                }
                Section("Техника") {
                    ForEach(steps) { step in
                        Text("\(step.number). \(step.text)")
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
