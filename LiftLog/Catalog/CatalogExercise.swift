import Foundation

struct CatalogExercise: Codable, Identifiable {
    let id: String
    let name: String
    let force: String?
    let level: String?
    let mechanic: String?
    let equipment: String?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let instructions: [String]
    let category: String

    /// `name` is the English original from `exercises.json`; this is what the UI shows.
    var localizedName: String { CatalogNames.localizedName(id: id, fallback: name) }

    /// Whether `query` is in either the English or the Russian name, whatever the
    /// interface language (plans/features/localization, decision 5).
    func matches(_ query: String) -> Bool {
        name.localizedCaseInsensitiveContains(query)
            || CatalogNames.russianName(id: id)?.localizedCaseInsensitiveContains(query) == true
    }
}
