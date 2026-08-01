import SwiftUI

struct CatalogView: View {
    private let groups = ExerciseCatalog.grouped()

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.muscle) { group in
                    Section {
                        ForEach(group.exercises) { exercise in
                            NavigationLink {
                                CatalogExerciseDetailView(exercise: exercise)
                            } label: {
                                Text(exercise.name)
                                    .font(.sans(16))
                                    .foregroundStyle(.ink)
                            }
                            .listRowBackground(Color.chalk)
                            .listRowSeparatorTint(.hairline)
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
            .navigationTitle("Каталог")
        }
    }
}
