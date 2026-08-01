import SwiftUI
import SwiftData

enum TemplateSheet: Identifiable {
    case picker
    case defaults(Exercise)

    var id: String {
        switch self {
        case .picker: return "picker"
        case .defaults(let exercise): return "defaults-\(exercise.persistentModelID)"
        }
    }
}

struct TemplateDetailView: View {
    @Bindable var template: WorkoutTemplate
    let restTimer: RestTimer
    @Environment(\.modelContext) private var context

    @State private var activeSheet: TemplateSheet?
    @State private var startedWorkout: Workout?

    @Query(filter: #Predicate<Workout> { $0.completedAt == nil })
    private var activeWorkouts: [Workout]

    private var groupedItems: [(exercise: Exercise, items: [TemplateItem])] {
        var order: [PersistentIdentifier] = []
        var groups: [PersistentIdentifier: (Exercise, [TemplateItem])] = [:]

        for item in template.sortedItems {
            guard let exercise = item.exercise else { continue }
            let id = exercise.persistentModelID
            if groups[id] == nil {
                groups[id] = (exercise, [])
                order.append(id)
            }
            groups[id]?.1.append(item)
        }

        return order.compactMap { id in groups[id].map { (exercise: $0.0, items: $0.1) } }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Название шаблона", text: $template.name)
                .font(.display(24))
                .foregroundStyle(.ink)
                .padding()

            itemsList
            bottomButtons
        }
        .background(.chalk)
        .navigationTitle(template.name.isEmpty ? "Шаблон" : template.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .fullScreenCover(item: $startedWorkout) { workout in
            ActiveWorkoutView(workout: workout, restTimer: restTimer)
        }
    }

    private var itemsList: some View {
        List {
            ForEach(groupedItems, id: \.exercise.persistentModelID) { group in
                Section {
                    ForEach(group.items) { item in
                        itemRow(item)
                    }
                    .onDelete { offsets in delete(group.items, at: offsets) }
                } header: {
                    Text(group.exercise.name).font(.sans(15)).foregroundStyle(.ink)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(.chalk)
    }

    private func itemRow(_ item: TemplateItem) -> some View {
        HStack {
            Text(item.defaultWeight.formatted(.number) + " кг")
                .font(.mono(14)).foregroundStyle(.ink)
            Spacer()
            Text("× \(item.defaultReps)")
                .font(.mono(14)).foregroundStyle(.steel)
        }
        .listRowBackground(Color.chalk)
        .listRowSeparatorTint(.hairline)
    }

    private var bottomButtons: some View {
        VStack(spacing: 10) {
            Button("Добавить подход") { activeSheet = .picker }
                .font(.sans(15))
                .buttonStyle(.bordered)
                .tint(.plateBlue)

            if !template.items.isEmpty {
                if activeWorkouts.isEmpty {
                    Button("Начать тренировку по шаблону") { startFromTemplate() }
                        .font(.sans(15))
                        .buttonStyle(.borderedProminent)
                        .tint(.plateBlue)
                } else {
                    Text("Тренировка уже идёт — заверши её, чтобы начать по шаблону")
                        .font(.sans(13))
                        .foregroundStyle(.steel)
                }
            }
        }
        .padding()
    }

    @ViewBuilder
    private func sheetContent(for sheet: TemplateSheet) -> some View {
        switch sheet {
        case .picker:
            ExercisePickerView { exercise in
                activeSheet = .defaults(exercise)
            }
        case .defaults(let exercise):
            TemplateItemDefaultsView(template: template, exercise: exercise)
        }
    }

    private func startFromTemplate() {
        let workout = Workout()
        context.insert(workout)
        workout.applyTemplate(template)
        startedWorkout = workout
    }

    private func delete(_ items: [TemplateItem], at offsets: IndexSet) {
        for index in offsets {
            context.delete(items[index])
        }
    }
}
