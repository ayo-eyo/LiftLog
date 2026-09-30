import Foundation

/// Translated names of catalog exercises (plans/features/localization, stage 2). They live
/// in `ExerciseNames.xcstrings`, keyed by `CatalogExercise.id`; `exercises.json` keeps the
/// English originals, which stay the canonical `Exercise.name` in the store and in backups.
///
/// `nonisolated`: the CSV export runs off the main actor and names its rows the same way.
nonisolated enum CatalogNames {
    private static let table = "ExerciseNames"
    /// Marks "no entry" — `localizedString` hands back `value` for an unknown key.
    private static let missing = "\u{0}"

    /// Search matches both languages (decision 5), so «жим» finds the bench press on an
    /// English phone too — this is where the Russian comes from regardless of the UI's.
    private static let russianBundle: Bundle? = Bundle.main.path(forResource: "ru", ofType: "lproj").flatMap(Bundle.init(path:))

    /// The name to show; the English original when there's no translation. Straight from
    /// the bundle each time — it caches the table, so this is a dictionary lookup.
    static func localizedName(id: String, fallback: String) -> String {
        let name = Bundle.main.localizedString(forKey: id, value: missing, table: table)
        return name == missing ? fallback : name
    }

    static func russianName(id: String) -> String? {
        guard let name = russianBundle?.localizedString(forKey: id, value: missing, table: table), name != missing else { return nil }
        return name
    }
}

/// Catalog field values (`"lats"`, `"body only"`, `"beginner"`) → interface language. The
/// keys are the English display forms in `Localizable.xcstrings`; a value the catalog
/// doesn't use yet falls back to the capitalized raw string, as before.
nonisolated enum CatalogVocabulary {
    static func muscle(_ raw: String) -> String {
        switch raw {
        case "abdominals": String(localized: "Abdominals")
        case "abductors": String(localized: "Abductors")
        case "adductors": String(localized: "Adductors")
        case "biceps": String(localized: "Biceps")
        case "calves": String(localized: "Calves")
        case "chest": String(localized: "Chest")
        case "forearms": String(localized: "Forearms")
        case "glutes": String(localized: "Glutes")
        case "hamstrings": String(localized: "Hamstrings")
        case "lats": String(localized: "Lats")
        case "lower back": String(localized: "Lower back")
        case "middle back": String(localized: "Middle back")
        case "neck": String(localized: "Neck")
        case "quadriceps": String(localized: "Quadriceps")
        case "shoulders": String(localized: "Shoulders")
        case "traps": String(localized: "Traps")
        case "triceps": String(localized: "Triceps")
        case "other": String(localized: "Other")
        default: raw.capitalized
        }
    }

    static func equipment(_ raw: String) -> String {
        switch raw {
        case "bands": String(localized: "Bands")
        case "barbell": String(localized: "Barbell")
        case "body only": String(localized: "Bodyweight only")
        case "cable": String(localized: "Cable")
        case "dumbbell": String(localized: "Dumbbell")
        case "e-z curl bar": String(localized: "EZ curl bar")
        case "exercise ball": String(localized: "Exercise ball")
        case "foam roll": String(localized: "Foam roller")
        case "kettlebells": String(localized: "Kettlebells")
        case "machine": String(localized: "Machine")
        case "medicine ball": String(localized: "Medicine ball")
        case "other": String(localized: "Other")
        default: raw.capitalized
        }
    }

    static func level(_ raw: String) -> String {
        switch raw {
        case "beginner": String(localized: "Beginner")
        case "intermediate": String(localized: "Intermediate")
        case "expert": String(localized: "Expert")
        default: raw.capitalized
        }
    }

    static func force(_ raw: String) -> String {
        switch raw {
        case "pull": String(localized: "Pull")
        case "push": String(localized: "Push")
        case "static": String(localized: "Static")
        default: raw.capitalized
        }
    }

    static func muscles(_ raw: [String]) -> String {
        raw.map(muscle).joined(separator: ", ")
    }
}
