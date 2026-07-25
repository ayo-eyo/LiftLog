import SwiftUI

struct AnalyticsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Аналитика в разработке",
                systemImage: "chart.xyaxis.line",
                description: Text("Здесь появятся графики по весу, повторам и пульсу")
                )
            .navigationTitle("Аналитика")
        }
    }
}
