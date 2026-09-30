import Testing
import Foundation
@testable import LiftLog

/// plans/features/localization: English is the source language, Russian a translation in
/// the String Catalogs. The test plans run in Russian, so a key left untranslated would
/// show English in the middle of a Russian screen without failing any UI test — this is
/// what catches it.
@Suite("Локализация — каталоги строк")
struct LocalizationCatalogTests {
    private static let pluralCategories: Set<String> = ["one", "few", "many", "other"]

    @Test("у каждого ключа каждого каталога есть русский перевод", arguments: SourcePaths.stringCatalogs)
    func everyKeyHasRussian(catalog: URL) throws {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any]
        let strings = try #require(json?["strings"] as? [String: [String: Any]], "нет strings в \(catalog.lastPathComponent)")
        #expect(!strings.isEmpty)

        for (key, entry) in strings {
            let ru = (entry["localizations"] as? [String: Any])?["ru"] as? [String: Any]
            #expect(ru != nil, "\(catalog.lastPathComponent): «\(key)» без русского")
            guard let ru else { continue }
            if let variations = (ru["variations"] as? [String: Any])?["plural"] as? [String: Any] {
                // Russian needs all of one/few/many (1, 2, 5) — an `other` alone would make
                // «5 подхода».
                #expect(Self.pluralCategories.isSubset(of: Set(variations.keys)), "\(catalog.lastPathComponent): «\(key)» — неполные формы \(variations.keys.sorted())")
            } else {
                let state = (ru["stringUnit"] as? [String: Any])?["state"] as? String
                #expect(state == "translated", "\(catalog.lastPathComponent): «\(key)» — состояние \(state ?? "нет")")
            }
        }
    }
}

@Suite("Локализация — множественные формы")
struct LocalizationPluralTests {
    private static func bundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"), "нет \(language).lproj в приложении")
        return try #require(Bundle(path: path))
    }

    @Test("счёт подходов по-русски: 1 подход, 2 подхода, 5 подходов, 21 подход", arguments: [
        (1, "1 подход"), (2, "2 подхода"), (5, "5 подходов"), (11, "11 подходов"), (21, "21 подход"),
    ])
    func russianSetCount(count: Int, expected: String) throws {
        #expect(String(localized: "\(count) sets", bundle: try Self.bundle("ru")) == expected)
    }

    @Test("счёт подходов по-английски: 1 set, 2 sets", arguments: [(1, "1 set"), (2, "2 sets")])
    func englishSetCount(count: Int, expected: String) throws {
        #expect(String(localized: "\(count) sets", bundle: try Self.bundle("en")) == expected)
    }

    @Test("«N из M» согласуется с M в родительном: из 1 подхода, из 4 подходов, из 21 подхода", arguments: [
        (0, 1, "0 из 1 подхода"), (2, 4, "2 из 4 подходов"), (3, 5, "3 из 5 подходов"), (1, 21, "1 из 21 подхода"),
    ])
    func russianOfPlanned(logged: Int, planned: Int, expected: String) throws {
        #expect(String(localized: "\(logged) of \(planned) sets", bundle: try Self.bundle("ru")) == expected)
    }

    @Test("две множественные формы в одной строке склоняются независимо")
    func twoPluralsInOneString() throws {
        let exercises = 1
        let sets = 5
        #expect(String(localized: "\(exercises) exercises · \(sets) sets", bundle: try Self.bundle("ru")) == "1 упражнение · 5 подходов")
        #expect(String(localized: "\(exercises) exercises · \(sets) sets", bundle: try Self.bundle("en")) == "1 exercise · 5 sets")
    }

    @Test("английский без перевода показывает сам ключ — исходный язык")
    func englishFallsBackToKey() throws {
        #expect(String(localized: "Workout in progress", bundle: try Self.bundle("en")) == "Workout in progress")
        #expect(String(localized: "Workout in progress", bundle: try Self.bundle("ru")) == "Тренировка идёт")
    }
}
