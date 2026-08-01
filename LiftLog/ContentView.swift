import SwiftUI
import SwiftData

struct ContentView: View {
    @Query(sort: \Exercise.createdAt) private var exercises: [Exercise]

    var body: some View {
        NavigationStack {
            List(exercises) { exercise in
                NavigationLink {
                    ExerciseDetailView(exercise: exercise)
                } label: {
                    HStack {
                        Text(exercise.name)
                            .font(.sans(16))
                            .foregroundStyle(.ink)
                        if exercise.catalogID != nil {
                            Spacer()
                            Image(systemName: "books.vertical")
                                .foregroundStyle(.steel)
                                .font(.caption)
                        }
                    }
                }
                .listRowBackground(Color.chalk)
                .listRowSeparatorTint(.hairline)
            }
            .scrollContentBackground(.hidden)
            .background(.chalk)
            .navigationTitle("Тренировки")
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
