import Foundation
import SwiftData

/// Shared builders for `#Preview` blocks — the SwiftUI-canvas equivalent of
/// `LiftLogTests/Support/Fixtures.swift`, which previews can't reach (it lives in the
/// test target). Kept minimal and separate from the test fixtures on purpose: previews
/// must compile and render with zero dependency on anything outside the app target.
enum PreviewSupport {
    /// A fresh in-memory container per preview, so previews never touch the app's real
    /// on-disk store and never share state with each other.
    @MainActor
    static func container() -> ModelContainer {
        let configuration = ModelConfiguration(schema: LiftLogApp.schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: LiftLogApp.schema, configurations: configuration)
    }

    /// A `RestTimer` whose notification hooks are no-ops — same reasoning as
    /// `Fixtures.restTimer()` in the test target: previews never touch the real
    /// `UNUserNotificationCenter`.
    static func restTimer() -> RestTimer {
        RestTimer(scheduleNotification: { _, _ in }, cancelNotification: {})
    }
}
