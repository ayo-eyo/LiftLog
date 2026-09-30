import Foundation
import SwiftData

@Model
final class Exercise {
    var syncID: UUID = UUID()
    var name: String
    var createdAt: Date
    var catalogID: String?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.exercise) var sets: [WorkoutSet] = []

    init(name: String, catalogID: String? = nil, createdAt: Date = .now) {
        self.syncID = UUID()
        self.name = name
        self.catalogID = catalogID
        self.createdAt = createdAt
    }

    /// The name to show. A catalog exercise keeps its English original in `name` — that's
    /// what backups and the watch's by-name fallback rely on — and shows the translation;
    /// the user's own exercise is shown as they named it.
    var displayName: String {
        catalogID.map { CatalogNames.localizedName(id: $0, fallback: name) } ?? name
    }

    var catalogExercise: CatalogExercise? {
        catalogID.flatMap { ExerciseCatalog.byID[$0] }
    }

    var primaryMuscles: [String] { catalogExercise?.primaryMuscles ?? [] }
    var secondaryMuscles: [String] { catalogExercise?.secondaryMuscles ?? [] }
}
