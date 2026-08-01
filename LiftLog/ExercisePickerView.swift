import SwiftUI
import SwiftData

struct ExercisePickerView: View {
    @Bindable var workout: Workout
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var myExercises: [Exercise]

    @State private var searchText = ""
    private let groups = ExerciseCatalog.grouped()

    private var alreadyInWorkoutCatalogIDs: Set<String> {
        Set(workout.exercises.compactMap { $0.catalogID })
    }

    private var filteredGroups: [(muscle: String, exercises: [CatalogExercise])] {
        groups.compactMap { group in
            let filtered = group.exercises.filter { item in
                !alreadyInWorkoutCatalogIDs.contains(item.id) &&
                (searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText))
            }
            return filtered.isEmpty ? nil : (group.muscle, filtered)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredGroups, id: \.muscle) { group in
                    Section {
                        ForEach(group.exercises) { item in
                            Button(item.name) { add(item) }
                                .foregroundStyle(.ink)
                        }
                    } header: {
                        Text(group.muscle.capitalized)
                            .font(.mono(12))
                            .foregroundStyle(.steel)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(.chalk)
            .searchable(text: $searchText, prompt: "Поиск упражнения")
            .navigationTitle("Добавить упражнение")
            .toolbar {
                Button("Отмена") { dismiss() }
            }
        }
    }

    private func add(_ catalogExercise: CatalogExercise) {
        let exercise = ExerciseCatalog.exercise(for: catalogExercise, existing: myExercises, context: context)
        workout.addExercise(exercise)
        dismiss()
    }
}
