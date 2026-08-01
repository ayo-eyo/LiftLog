import SwiftUI
import SwiftData

struct TemplateListView: View {
    let restTimer: RestTimer

    @Query(sort: \WorkoutTemplate.createdAt, order: .reverse) private var templates: [WorkoutTemplate]
    @Environment(\.modelContext) private var context
    @State private var newTemplate: WorkoutTemplate?

    var body: some View {
        NavigationStack {
            List {
                ForEach(templates) { template in
                    NavigationLink {
                        TemplateDetailView(template: template, restTimer: restTimer)
                    } label: {
                        HStack {
                            Text(template.name).font(.sans(16)).foregroundStyle(.ink)
                            Spacer()
                            Text("\(template.items.count)")
                                .font(.mono(13))
                                .foregroundStyle(.steel)
                        }
                    }
                    .listRowBackground(Color.chalk)
                    .listRowSeparatorTint(.hairline)
                }
                .onDelete(perform: delete)
            }
            .scrollContentBackground(.hidden)
            .background(.chalk)
            .navigationTitle("Шаблоны")
            .toolbar {
                Button { createTemplate() } label: { Image(systemName: "plus") }
            }
            .overlay {
                if templates.isEmpty {
                    ContentUnavailableView(
                        "Шаблонов пока нет",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Нажми «+», чтобы создать первый")
                    )
                }
            }
            .navigationDestination(item: $newTemplate) { template in
                TemplateDetailView(template: template, restTimer: restTimer)
            }
        }
    }

    private func createTemplate() {
        let new = WorkoutTemplate(name: "Новый шаблон")
        context.insert(new)
        newTemplate = new
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(templates[index])
        }
    }
}
