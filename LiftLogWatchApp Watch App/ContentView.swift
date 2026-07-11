import SwiftUI

struct ContentView: View {
    @StateObject private var workout = WorkoutManager()

    var body: some View {
        VStack(spacing: 12) {
            Text("\(Int(workout.heartRate)) bpm")
                .font(.title2).bold()

            Button(workout.isRunning ? "Finish" : "Start") {
                workout.isRunning ? workout.end() : workout.start()
            }
        }
        .task { await workout.requestAuthorization() }
    }
}
