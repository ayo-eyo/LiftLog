import SwiftUI

struct CatalogView: View {
    @State private var searchText = ""
    private let groups = ExerciseCatalog.grouped()

    // Recomputed only when `searchText` actually changes (see .onChange below), instead
    // of on every render — same reasoning, and the same tested filter, as
    // `ExercisePickerView`, which filters this same ~870-entry catalog.
    @State private var filteredGroups: [(muscle: String, exercises: [CatalogExercise])] = []

    private func recomputeFilteredGroups() {
        filteredGroups = ExercisePickerView.filteredGroups(groups, excluding: [], searchText: searchText)
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
        .onAppear { recomputeFilteredGroups() }
        .onChange(of: searchText) { recomputeFilteredGroups() }
    }
}
