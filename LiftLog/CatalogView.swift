import SwiftUI

struct CatalogView: View {
    @State private var searchText = ""
    private let groups = ExerciseCatalog.grouped()

    private var filteredGroups: [(muscle: String, exercises: [CatalogExercise])] {
        guard !searchText.isEmpty else { return groups }
        return groups.compactMap { group in
            let filtered = group.exercises.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            return filtered.isEmpty ? nil : (group.muscle, filtered)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredGroups, id: \.muscle) { group in
                    Section {
                        ForEach(group.exercises) { exercise in
                            NavigationLink {
                                CatalogExerciseDetailView(exercise: exercise)
                            } label: {
                                Text(exercise.name).font(.sans(16)).foregroundStyle(.ink)
                            }
                            .listRowBackground(Color.chalk)
                            .listRowSeparatorTint(.hairline)
                        }
                    } header: {
                        Text(group.muscle.capitalized).font(.mono(12)).foregroundStyle(.steel)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(.chalk)
            .searchable(text: $searchText, prompt: "Поиск упражнения")
            .navigationTitle("Каталог")
        }
    }
}
