import Testing
import SwiftUI
@testable import LiftLog

@Suite("MuscleAtlas — покрытие мышц из exercises.json")
struct MuscleAtlasCoverageTests {
    /// Every muscle name that actually appears in the bundled dataset — the set the
    /// app needs `MuscleAtlas` to cover, not an arbitrary fixed list, so this stays
    /// correct if the dataset changes.
    static let musclesInCatalog: Set<String> = {
        var set = Set<String>()
        for exercise in ExerciseCatalog.all {
            set.formUnion(exercise.primaryMuscles)
            set.formUnion(exercise.secondaryMuscles)
        }
        return set
    }()

    @Test("каждое имя мышцы из exercises.json подсвечивает хотя бы одну сторону, иначе упражнение рисуется пустым силуэтом")
    func everyCatalogMuscleHasAtlasEntry() {
        for muscle in Self.musclesInCatalog {
            let front = MuscleAtlas.frontSlugs(for: [muscle])
            let back = MuscleAtlas.backSlugs(for: [muscle])
            #expect(!front.isEmpty || !back.isEmpty, "мышца \"\(muscle)\" не подсвечивает ни одного региона")
        }
    }

    @Test("каждый front-slug существует среди front-регионов MuscleMapData")
    func frontSlugsExistAmongFrontRegions() {
        let frontRegionSlugs = Set(MuscleMapData.front.map(\.slug))
        for muscle in Self.musclesInCatalog {
            for slug in MuscleAtlas.frontSlugs(for: [muscle]) {
                #expect(frontRegionSlugs.contains(slug), "slug \"\(slug)\" (мышца \"\(muscle)\") не найден среди front-регионов")
            }
        }
    }

    @Test("каждый back-slug существует среди back-регионов MuscleMapData")
    func backSlugsExistAmongBackRegions() {
        let backRegionSlugs = Set(MuscleMapData.back.map(\.slug))
        for muscle in Self.musclesInCatalog {
            for slug in MuscleAtlas.backSlugs(for: [muscle]) {
                #expect(backRegionSlugs.contains(slug), "slug \"\(slug)\" (мышца \"\(muscle)\") не найден среди back-регионов")
            }
        }
    }
}

@Suite("MuscleAtlas.preferredSide")
struct MuscleAtlasPreferredSideTests {
    @Test("primary на фронте выбирает .front")
    func primaryFrontChoosesFront() {
        #expect(MuscleAtlas.preferredSide(primary: ["chest"], secondary: []) == .front)
    }

    @Test("primary только на спине выбирает .back")
    func primaryBackOnlyChoosesBack() {
        #expect(MuscleAtlas.preferredSide(primary: ["glutes"], secondary: []) == .back)
    }

    @Test("пустой primary, secondary на фронте выбирает .front")
    func emptyPrimarySecondaryFrontChoosesFront() {
        #expect(MuscleAtlas.preferredSide(primary: [], secondary: ["biceps"]) == .front)
    }

    @Test("всё пусто выбирает .front по умолчанию")
    func everythingEmptyDefaultsToFront() {
        #expect(MuscleAtlas.preferredSide(primary: [], secondary: []) == .front)
    }
}

@Suite("MuscleMapData — целостность геометрии")
struct MuscleMapDataTests {
    @Test("slug'и уникальны внутри каждой стороны")
    func slugsAreUniqueWithinSide() {
        let frontSlugs = MuscleMapData.front.map(\.slug)
        let backSlugs = MuscleMapData.back.map(\.slug)
        #expect(Set(frontSlugs).count == frontSlugs.count, "дубли slug'ов среди front-регионов")
        #expect(Set(backSlugs).count == backSlugs.count, "дубли slug'ов среди back-регионов")
    }

    @Test("каждый регион парсится в непустой Path")
    func everyRegionParsesToNonEmptyPath() {
        for region in MuscleMap.frontRegions {
            #expect(!region.path.boundingRect.isEmpty || !region.path.isEmpty, "front-регион \"\(region.slug)\" пустой")
        }
        for region in MuscleMap.backRegions {
            #expect(!region.path.boundingRect.isEmpty || !region.path.isEmpty, "back-регион \"\(region.slug)\" пустой")
        }
    }

    @Test("front-координаты укладываются в 0...724 по x, back — в 724...1448")
    func coordinateConventionHoldsForXAxis() {
        for region in MuscleMap.frontRegions {
            let rect = region.path.boundingRect
            #expect(rect.minX >= 0 && rect.maxX <= 724, "front-регион \"\(region.slug)\" вышел за 0...724 по x: \(rect)")
        }
        for region in MuscleMap.backRegions {
            let rect = region.path.boundingRect
            #expect(rect.minX >= 724 && rect.maxX <= 1448, "back-регион \"\(region.slug)\" вышел за 724...1448 по x: \(rect)")
        }
    }

    @Test("обе стороны укладываются в 0...1448 по y")
    func coordinateConventionHoldsForYAxis() {
        for region in MuscleMap.frontRegions + MuscleMap.backRegions {
            let rect = region.path.boundingRect
            #expect(rect.minY >= 0 && rect.maxY <= 1448, "регион \"\(region.slug)\" вышел за 0...1448 по y: \(rect)")
        }
    }
}
