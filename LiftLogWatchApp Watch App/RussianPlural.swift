import Foundation

/// Picks the correct Russian plural form for a count (e.g. "1 подход", "2 подхода",
/// "5 подходов"). Duplicated verbatim in the iOS target, same as `WorkoutSyncModels.swift`,
/// since the two targets don't share a framework.
enum RussianPlural {
    static func form(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n = abs(count) % 100
        let n1 = n % 10
        if (11...14).contains(n) {
            return many
        }
        switch n1 {
        case 1: return one
        case 2, 3, 4: return few
        default: return many
        }
    }
}
