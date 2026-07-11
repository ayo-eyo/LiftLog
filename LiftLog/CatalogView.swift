import SwiftUI

struct CatalogView: View {
    private let groups = ExerciseCatalog.grouped()

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.muscle) { group in
                    Section(group.muscle.capitalized) {
                        ForEach(group.exercises) { exercise in
                            NavigationLink(exercise.name) {
                                CatalogExerciseDetailView(exercise: exercise)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Каталог")
        }
    }
}
