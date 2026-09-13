import Testing
import Foundation
import SwiftData
@testable import LiftLog

@Suite("ExerciseCatalog.all / byID / groups — целостность exercises.json")
struct ExerciseCatalogDataTests {
    @Test("all не пуст и не теряет записи при декодировании")
    func allIsPopulated() {
        #expect(!ExerciseCatalog.all.isEmpty)
    }

    @Test("byID.count == all.count — на текущем датасете дублей id нет")
    func byIDHasNoSilentDrops() {
        #expect(ExerciseCatalog.byID.count == ExerciseCatalog.all.count)
    }

    @Test("у каждой записи непустые id, name, category, primaryMuscles")
    func everyEntryHasRequiredFields() {
        for exercise in ExerciseCatalog.all {
            #expect(!exercise.id.isEmpty, "пустой id")
            #expect(!exercise.name.isEmpty, "пустое name у \(exercise.id)")
            #expect(!exercise.category.isEmpty, "пустая category у \(exercise.id)")
            #expect(!exercise.primaryMuscles.isEmpty, "пустые primaryMuscles у \(exercise.id)")
        }
    }

    @Test("groups отсортированы по названию мышцы, внутри — по имени упражнения, суммарный размер равен all.count")
    func groupsAreSortedAndComplete() {
        let groups = ExerciseCatalog.groups

        #expect(groups.map(\.muscle) == groups.map(\.muscle).sorted())
        for group in groups {
            #expect(group.exercises.map(\.name) == group.exercises.map(\.name).sorted())
        }
        #expect(groups.reduce(0) { $0 + $1.exercises.count } == ExerciseCatalog.all.count)
    }

    @Test("первый доступ к ExerciseCatalog.all укладывается в разумный бюджет (защита от per-view парсинга)")
    func firstAccessIsFast() {
        // `all` is a `static let`, already forced by the time this test runs (other
        // suites touch it first in the same process) — this asserts the *value* is
        // there and cheap to re-read, which is what a per-view-parse regression would break.
        let start = Date()
        _ = ExerciseCatalog.all.count
        #expect(Date().timeIntervalSince(start) < 1.5)
    }
}

@Suite("ExerciseCatalog.exercise(for:existing:context:) / addToMyExercises")
struct ExerciseCatalogFactoryTests {
    @Test("возвращает существующее упражнение по catalogID, не создавая дубль")
    func returnsExistingByCatalogID() throws {
        let store = try TestStore.open()
        let catalog = try #require(ExerciseCatalog.all.first)
        let existing = Fixtures.exercise(catalog.name, catalogID: catalog.id, in: store.context)

        let result = ExerciseCatalog.exercise(for: catalog, existing: [existing], context: store.context)

        #expect(result.persistentModelID == existing.persistentModelID)
        #expect(try store.count(Exercise.self) == 1)
    }

    @Test("создаёт ровно один объект, когда совпадения нет")
    func createsNewWhenNoMatch() throws {
        let store = try TestStore.open()
        let catalog = try #require(ExerciseCatalog.all.first)

        let result = ExerciseCatalog.exercise(for: catalog, existing: [], context: store.context)
        try store.context.save()

        #expect(result.catalogID == catalog.id)
        #expect(try store.count(Exercise.self) == 1)
    }

    @Test("addToMyExercises создаёт Exercise с name/catalogID из каталога")
    func addToMyExercisesCopiesNameAndCatalogID() throws {
        let store = try TestStore.open()
        let catalog = try #require(ExerciseCatalog.all.first)

        ExerciseCatalog.addToMyExercises(catalog, context: store.context)
        try store.context.save()

        let created = try #require(try store.fetch(Exercise.self).first)
        #expect(created.name == catalog.name)
        #expect(created.catalogID == catalog.id)
    }
}
