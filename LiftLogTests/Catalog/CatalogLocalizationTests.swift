import Testing
import Foundation
import SwiftData
@testable import LiftLog

/// Stage 2 of plans/features/localization. The test plans run in Russian, so "localized"
/// below means Russian.
@Suite("Каталог — переведённые названия")
struct CatalogNamesTests {
    private static let benchID = "Barbell_Bench_Press_-_Medium_Grip"

    @Test("у каждого упражнения каталога есть запись в ExerciseNames.xcstrings — и лишних нет")
    func namesCoverTheWholeCatalog() throws {
        let url = try #require(SourcePaths.stringCatalogs.first { $0.lastPathComponent == "ExerciseNames.xcstrings" })
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let strings = json?["strings"] as? [String: Any] ?? [:]
        let keys = Set(strings.keys)

        #expect(keys == Set(ExerciseCatalog.all.map(\.id)))
    }

    @Test("название упражнения каталога — на языке интерфейса, оригинал не меняется")
    func localizedNameIsTranslated() throws {
        let bench = try #require(ExerciseCatalog.byID[Self.benchID])

        #expect(bench.localizedName == "Жим штанги лёжа средним хватом")
        #expect(bench.name == "Barbell Bench Press - Medium Grip")
    }

    @Test("поиск находит упражнение и по-русски, и по-английски, без учёта регистра", arguments: [
        "жим штанги лёжа средним", "Bench Press - Medium", "BARBELL BENCH",
    ])
    func searchMatchesBothLanguages(query: String) {
        let found = ExercisePickerView.filteredGroups(ExerciseCatalog.groups, excluding: [], searchText: query)
            .flatMap(\.exercises)
            .map(\.id)

        #expect(found.contains(Self.benchID))
    }

    @Test("внутри группы упражнения идут по алфавиту перевода")
    func groupsAreSortedByTranslatedName() throws {
        let group = try #require(ExerciseCatalog.groups.first)
        let names = group.exercises.map(\.localizedName)

        #expect(names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    @Test("displayName: у упражнения каталога — перевод, у своего — как назвал пользователь")
    func displayName() throws {
        let store = try TestStore.open()
        let catalogBacked = Fixtures.catalogBackedExercise(in: store.context)
        let own = Fixtures.exercise("Жим Ларсена", in: store.context)

        #expect(catalogBacked.displayName == "Жим штанги лёжа средним хватом")
        #expect(catalogBacked.name == "Barbell Bench Press - Medium Grip")
        #expect(own.displayName == "Жим Ларсена")
    }
}

@Suite("Каталог — справочники")
struct CatalogVocabularyTests {
    @Test("значения каталога переводятся", arguments: [
        (CatalogVocabulary.muscle("lats"), "Широчайшие"),
        (CatalogVocabulary.muscle("lower back"), "Поясница"),
        (CatalogVocabulary.equipment("body only"), "Собственный вес"),
        (CatalogVocabulary.level("beginner"), "Новичок"),
        (CatalogVocabulary.force("pull"), "Тянущее"),
    ])
    func translates(value: String, expected: String) {
        #expect(value == expected)
    }

    @Test("каждая мышца каталога переведена, а не показана сырой строкой")
    func everyCatalogMuscleIsTranslated() {
        let muscles = Set(ExerciseCatalog.all.flatMap { $0.primaryMuscles + $0.secondaryMuscles })
        for muscle in muscles {
            #expect(CatalogVocabulary.muscle(muscle) != muscle.capitalized, "«\(muscle)» без перевода")
        }
    }

    @Test("каждое оборудование, уровень и усилие каталога переведены")
    func everyCatalogValueIsTranslated() {
        for equipment in Set(ExerciseCatalog.all.compactMap(\.equipment)) {
            #expect(CatalogVocabulary.equipment(equipment) != equipment.capitalized, "оборудование «\(equipment)» без перевода")
        }
        for level in Set(ExerciseCatalog.all.compactMap(\.level)) {
            #expect(CatalogVocabulary.level(level) != level.capitalized, "уровень «\(level)» без перевода")
        }
        for force in Set(ExerciseCatalog.all.compactMap(\.force)) {
            #expect(CatalogVocabulary.force(force) != force.capitalized, "усилие «\(force)» без перевода")
        }
    }

    @Test("неизвестное значение показывается как раньше — с заглавной буквы")
    func unknownFallsBack() {
        #expect(CatalogVocabulary.muscle("serratus anterior") == "Serratus Anterior")
    }
}
