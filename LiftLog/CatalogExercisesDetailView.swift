import SwiftUI
import SwiftData

struct CatalogExerciseDetailView: View {
    let exercise: CatalogExercise
    @Environment(\.modelContext) private var context
    
    @Query private var myExercises: [Exercise]
    
    private var alreadyAdded: Bool {
        myExercises.contains { $0.catalogID == exercise.id }
    }

    var body: some View {
        List {
            Section {
                Button(alreadyAdded ? "Уже добавлено" : "Добавить себе") {
                    ExerciseCatalog.addToMyExercises(exercise, context: context)
                }
                .disabled(alreadyAdded)
            }
            
            
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
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
