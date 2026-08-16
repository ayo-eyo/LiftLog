import Foundation
import SwiftData
@testable import LiftLog

/// In-memory SwiftData stack for tests.
///
/// Every call to `makeContext()` builds a brand-new container, so suites never
/// share state and nothing touches the on-disk store the app uses. The schema is
/// listed explicitly (the app infers it from `Exercise` via relationships) so a
/// model that gets orphaned from the graph still fails loudly here.
@MainActor
enum TestStore {
    static let schema = Schema([
        Exercise.self,
        Workout.self,
        WorkoutSet.self,
        WorkoutTemplate.self,
        TemplateItem.self,
    ])

    static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    /// The usual entry point: a fresh context backed by its own in-memory store.
    /// Hold on to the returned container for as long as the context is used —
    /// the context does not keep it alive.
    static func makeContext() throws -> (context: ModelContext, container: ModelContainer) {
        let container = try makeContainer()
        return (ModelContext(container), container)
    }
}

/// Convenience wrapper so a suite can declare `let store = try TestStore.open()`
/// and use `store.context` without juggling the container's lifetime.
@MainActor
final class TestStoreHandle {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try TestStore.makeContainer()
        context = ModelContext(container)
    }

    /// Forces a save + fresh read, to prove something actually persisted rather
    /// than only living in the context's in-memory changes.
    func reload() throws -> ModelContext {
        try context.save()
        return ModelContext(container)
    }

    func fetch<T: PersistentModel>(_ type: T.Type = T.self, sortBy: [SortDescriptor<T>] = []) throws -> [T] {
        try context.fetch(FetchDescriptor<T>(sortBy: sortBy))
    }

    func count<T: PersistentModel>(_ type: T.Type = T.self) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }
}

extension TestStore {
    static func open() throws -> TestStoreHandle {
        try TestStoreHandle()
    }
}
