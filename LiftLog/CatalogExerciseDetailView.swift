import SwiftUI

struct CatalogExerciseDetailView: View {
    let exercise: CatalogExercise

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
                    ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
