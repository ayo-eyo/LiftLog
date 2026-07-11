import Foundation
import SwiftData

enum ExerciseCatalog {
    static func load() -> [CatalogExercise] {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json") else {
            print("❌ exercises.json не найден в бандле")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([CatalogExercise].self, from: data)
        } catch {
            print("❌ Ошибка декодирования: \(error)")
            return []
        }
    }
    
    static func grouped() -> [(muscle: String, exercises: [CatalogExercise])] {
        let all = load()
        let groups = Dictionary(grouping: all) { $0.primaryMuscles.first ?? "other" }
        return groups
            .map{ ( muscle: $0.key, exercises: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.muscle < $1.muscle }
    }
    
    static func addToMyExercises(_ catalogExercise: CatalogExercise, context: ModelContext) {
        let new = Exercise(name: catalogExercise.name, catalogID: catalogExercise.id)
        context.insert(new)
    }
}
