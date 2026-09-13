//
//  LiftLogWatchAppApp.swift
//  LiftLogWatchApp Watch App
//
//  Created by Artem Sherstnev on 30.06.2026.
//

import SwiftUI
import WatchKit
import HealthKit

/// HealthKit's two ways into this app that don't go through the UI.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    /// The phone started a workout and launched this app for it
    /// (`HealthKitManager.startWatchWorkout`). The session itself starts once the phone's
    /// context names the workout — ask for it right away instead of waiting.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        PhoneSessionManager.shared.requestContext()
    }

    /// Relaunched with a workout session still running.
    func handleActiveWorkoutRecovery() {
        Task { await WorkoutRecorder.shared.recover() }
    }
}

@main
struct LiftLogWatchApp_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
