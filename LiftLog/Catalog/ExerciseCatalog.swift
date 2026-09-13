import Foundation
import SwiftData
import os

enum ExerciseCatalog {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LiftLog", category: "ExerciseCatalog")

    static let all: [CatalogExercise] = load()

    static let byID: [String: CatalogExercise] = Dictionary(
        all.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    static let groups: [(muscle: String, exercises: [CatalogExercise])] = {
        let byMuscle = Dictionary(grouping: all) { $0.primaryMuscles.first ?? "other" }
        return byMuscle
            .map { (muscle: $0.key, exercises: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.muscle < $1.muscle }
    }()

    private static func load() -> [CatalogExercise] {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json") else {
            logger.error("exercises.json не найден в бандле")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([CatalogExercise].self, from: data)
        } catch {
            logger.error("Ошибка декодирования exercises.json: \(error.localizedDescription)")
            return []
        }
    }

    static func grouped() -> [(muscle: String, exercises: [CatalogExercise])] {
        groups
    }

    static func addToMyExercises(_ catalogExercise: CatalogExercise, context: ModelContext) {
        let new = Exercise(name: catalogExercise.name, catalogID: catalogExercise.id)
        context.insert(new)
    }
    
    static func exercise(for catalogExercise: CatalogExercise, existing: [Exercise], context: ModelContext) -> Exercise {
        if let found = existing.first(where: { $0.catalogID == catalogExercise.id}) {
            return found
        }
        let new = Exercise(name: catalogExercise.name, catalogID: catalogExercise.id)
        context.insert(new)
        return new
    }
}
