import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.createdAt) private var exercises: [Exercise]

    var body: some View {
        NavigationStack {
            List(exercises) { exercise in
                NavigationLink {
                    ExerciseDetailView(exercise: exercise)
                } label: {
                    Text(exercise.name)
                    if exercise.catalogID != nil {
                        Spacer()
                        Image(systemName: "books.vertical")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Упражнения")
            .toolbar {
                NavigationLink {
                    CatalogView()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}
