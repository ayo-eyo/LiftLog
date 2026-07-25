import SwiftUI

struct TemplatesPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Шаблонов пока нет",
                systemImage: "list.bullet.rectangle",
                description: Text("Здесь появятся заголовки тренировок")
                )
            .navigationTitle("Шаблоны")
        }
    }
}
