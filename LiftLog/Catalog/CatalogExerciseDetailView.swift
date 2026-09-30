import SwiftUI
import SwiftData

struct CatalogExerciseDetailView: View {
    let exercise: CatalogExercise
    /// The user's own `Exercise` for this catalog entry, if they've ever added it —
    /// `ExerciseCatalog.exercise(for:existing:context:)` keeps it to one per `catalogID`.
    @Query private var owned: [Exercise]

    init(exercise: CatalogExercise) {
        self.exercise = exercise
        let catalogID: String? = exercise.id
        _owned = Query(filter: #Predicate<Exercise> { $0.catalogID == catalogID })
    }

    /// Shown only once there's history to look at (FR-2 entry points).
    private var progressExercise: Exercise? {
        owned.first { !$0.sets.isEmpty }
    }

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
            // The original next to the translation: it's what videos and coaches call it,
            // and the instructions below are still in English.
            if exercise.localizedName != exercise.name {
                Text(verbatim: exercise.name)
                    .font(.sans(13))
                    .foregroundStyle(.steel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .accessibilityIdentifier("catalogExercise.originalName")
            }
            List {
                if let progressExercise {
                    Section {
                        NavigationLink("My progress") {
                            ExerciseDetailView(exercise: progressExercise)
                        }
                        .font(.sans(15))
                        .foregroundStyle(.plateBlue)
                        .accessibilityIdentifier("catalogExercise.progress")
                    }
                }
                Section("Muscles") {
                    LabeledContent("Primary", value: CatalogVocabulary.muscles(exercise.primaryMuscles))
                    if !exercise.secondaryMuscles.isEmpty {
                        LabeledContent("Secondary", value: CatalogVocabulary.muscles(exercise.secondaryMuscles))
                    }
                }
                Section("Details") {
                    if let equipment = exercise.equipment {
                        LabeledContent("Equipment", value: CatalogVocabulary.equipment(equipment))
                    }
                    if let level = exercise.level {
                        LabeledContent("Level", value: CatalogVocabulary.level(level))
                    }
                    if let force = exercise.force {
                        LabeledContent("Force", value: CatalogVocabulary.force(force))
                    }
                }
                Section("Technique") {
                    ForEach(steps) { step in
                        Text("\(step.number). \(step.text)")
                    }
                }
            }
        }
        .navigationTitle(exercise.localizedName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
