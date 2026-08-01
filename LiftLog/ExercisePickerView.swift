import SwiftUI
import SwiftData

struct ExercisePickerView: View {
    var excluding: Set<String> = []
    var onSelect: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var myExercises: [Exercise]

    @State private var searchText = ""
    private let groups = ExerciseCatalog.grouped()

    private var filteredGroups: [(muscle: String, exercises: [CatalogExercise])] {
        groups.compactMap { group in
            let filtered = group.exercises.filter { item in
                !excluding.contains(item.id) &&
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
                            Button(item.name) { select(item) }
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

    private func select(_ catalogExercise: CatalogExercise) {
        let exercise = ExerciseCatalog.exercise(for: catalogExercise, existing: myExercises, context: context)
        onSelect(exercise)
        dismiss()
    }
}
