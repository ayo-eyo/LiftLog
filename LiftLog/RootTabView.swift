import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Тренировки", systemImage: "figure.strengthtraining.traditional") {
                ContentView()
            }
            Tab("Шаблоны", systemImage: "list.bullet.rectangle") {
                TemplatesPlaceholderView()
            }
            Tab("Упражнения", systemImage: "books.vertical") {
                CatalogView()
            }
            Tab("Аналитика", systemImage: "chart.xyaxis.line") {
                AnalyticsPlaceholderView()
            }
        }
        .tabViewBottomAccessory {
            Label("Начать тренировку", systemImage: "play.fill")
        }
        .tint(.plateBlue)
    }
}
