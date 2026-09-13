import Foundation
import Testing
import SwiftData
@testable import LiftLog

/// A store with every kind of history the backup has to carry: a finished workout, a
/// plan, a set logged outside any workout, and an exercise with no sets at all.
@MainActor
private func populate(_ context: ModelContext) {
    let bench = Fixtures.exercise("Жим лёжа", catalogID: "Barbell_Bench_Press_-_Medium_Grip", in: context)
    let squat = Fixtures.exercise("Присед", createdAt: Fixtures.date(offset: 1), in: context)
    Fixtures.exercise("Тяга", createdAt: Fixtures.date(offset: 2), in: context)
    Fixtures.completedWorkout(bench, sets: [(60, 8), (65, 6)], on: Fixtures.day(1), name: "Грудь", in: context)
    Fixtures.workout(date: Fixtures.day(3), name: "Ноги", startedAt: nil, items: [(squat, 100, 5), (squat, 100, 5)], in: context)
    Fixtures.standaloneSet(weight: 70, reps: 3, for: bench, at: Fixtures.day(2), in: context)
}

@Suite("Резервная копия — полный цикл")
struct BackupRoundTripTests {
    @Test("экспорт → файл → импорт в пустой стор даёт ту же историю")
    func roundTripIntoEmptyStoreKeepsHistory() throws {
        let source = try TestStore.open()
        populate(source.context)
        let exported = try BackupExporter.makeFile(context: source.context, now: Fixtures.day(10))

        let decoded = try BackupImporter.decode(BackupExporter.encodeJSON(exported))
        let target = try TestStore.open()
        let result = try BackupImporter.apply(decoded, context: target.context)

        #expect(decoded == exported)
        #expect(result == ImportResult(addedWorkouts: 2, addedExercises: 3, addedStandaloneSets: 1))
        #expect(try BackupExporter.makeFile(context: target.context, now: Fixtures.day(10)) == exported)
    }

    @Test("импортированная история работает как своя: подходы привязаны и к тренировке, и к упражнению")
    func importedSetsAreWiredToWorkoutAndExercise() throws {
        let source = try TestStore.open()
        populate(source.context)
        let target = try TestStore.open()

        try BackupImporter.apply(BackupExporter.makeFile(context: source.context), context: target.context)

        let workout = try #require(try target.fetch(Workout.self).first { $0.name == "Грудь" })
        let bench = try #require(try target.fetch(Exercise.self).first { $0.name == "Жим лёжа" })
        #expect(workout.setsFor(bench).map { $0.weight } == [60, 65])
        #expect(bench.sets.count == 3)
        #expect(workout.status == .completed)
    }

    @Test("повторный импорт того же файла ничего не добавляет")
    func secondImportAddsNothing() throws {
        let source = try TestStore.open()
        populate(source.context)
        let file = try BackupExporter.makeFile(context: source.context)
        let target = try TestStore.open()
        try BackupImporter.apply(file, context: target.context)

        let preview = try BackupImporter.preview(file, context: target.context)
        let result = try BackupImporter.apply(file, context: target.context)

        #expect(!preview.hasChanges)
        #expect(preview.existingWorkouts == 2)
        #expect(result == ImportResult())
        #expect(try target.count(WorkoutSet.self) == 3)
        #expect(try target.count(Exercise.self) == 3)
    }

    @Test("предпросмотр ничего не пишет")
    func previewWritesNothing() throws {
        let source = try TestStore.open()
        populate(source.context)
        let target = try TestStore.open()

        let preview = try BackupImporter.preview(BackupExporter.makeFile(context: source.context), context: target.context)

        #expect(preview == ImportPreview(newWorkouts: 2, existingWorkouts: 0, newExercises: 3, newStandaloneSets: 1))
        #expect(try target.count(Workout.self) == 0)
        #expect(try target.count(Exercise.self) == 0)
    }
}

@Suite("Резервная копия — слияние с существующими данными")
struct BackupMergeTests {
    @Test("добавляются только недостающие тренировки, существующие не перезаписываются")
    func addsMissingWorkoutsWithoutOverwriting() throws {
        let source = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: source.context)
        Fixtures.completedWorkout(bench, sets: [(60, 8)], on: Fixtures.day(1), name: "Первая", in: source.context)
        let file = try BackupExporter.makeFile(context: source.context)
        Fixtures.completedWorkout(bench, sets: [(65, 5)], on: Fixtures.day(2), name: "Вторая", in: source.context)
        let fullFile = try BackupExporter.makeFile(context: source.context)

        let target = try TestStore.open()
        try BackupImporter.apply(file, context: target.context)
        let local = try #require(try target.fetch(Workout.self).first)
        local.name = "Переименована здесь"

        let result = try BackupImporter.apply(fullFile, context: target.context)

        #expect(result.addedWorkouts == 1)
        #expect(result.addedExercises == 0)
        #expect(Set(try target.fetch(Workout.self).map(\.name)) == ["Переименована здесь", "Вторая"])
    }

    @Test("упражнение из файла сливается с существующим по catalogID, история общая")
    func exerciseMergesByCatalogID() throws {
        let source = try TestStore.open()
        let fileBench = Fixtures.exercise("Bench press", catalogID: "Barbell_Bench_Press_-_Medium_Grip", in: source.context)
        Fixtures.completedWorkout(fileBench, sets: [(60, 8)], on: Fixtures.day(1), in: source.context)

        let target = try TestStore.open()
        let localBench = Fixtures.exercise("Жим лёжа", catalogID: "Barbell_Bench_Press_-_Medium_Grip", in: target.context)
        Fixtures.completedWorkout(localBench, sets: [(55, 10)], on: Fixtures.day(0), in: target.context)

        let result = try BackupImporter.apply(BackupExporter.makeFile(context: source.context), context: target.context)

        #expect(result.addedExercises == 0)
        #expect(try target.count(Exercise.self) == 1)
        #expect(localBench.sets.map { $0.weight }.sorted() == [55, 60])
    }

    @Test("упражнение без catalogID сливается с существующим по имени")
    func customExerciseMergesByName() throws {
        let source = try TestStore.open()
        let fileExercise = Fixtures.exercise("Жим гантелей на скамье под углом", in: source.context)
        Fixtures.completedWorkout(fileExercise, sets: [(20, 10)], on: Fixtures.day(1), in: source.context)

        let target = try TestStore.open()
        let local = Fixtures.exercise("Жим гантелей на скамье под углом", in: target.context)

        try BackupImporter.apply(BackupExporter.makeFile(context: source.context), context: target.context)

        #expect(try target.count(Exercise.self) == 1)
        #expect(local.sets.count == 1)
    }

    @Test("подход вне тренировки, который уже есть, не дублируется")
    func existingStandaloneSetIsNotDuplicated() throws {
        let source = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: source.context)
        Fixtures.standaloneSet(weight: 70, reps: 3, for: bench, at: Fixtures.day(2), in: source.context)
        Fixtures.standaloneSet(weight: 72.5, reps: 2, for: bench, at: Fixtures.day(3), in: source.context)
        let file = try BackupExporter.makeFile(context: source.context)

        let target = try TestStore.open()
        let local = Fixtures.exercise("Жим лёжа", in: target.context)
        Fixtures.standaloneSet(weight: 70, reps: 3, for: local, at: Fixtures.day(2), in: target.context)

        let result = try BackupImporter.apply(file, context: target.context)

        #expect(result.addedStandaloneSets == 1)
        #expect(local.sets.map { $0.weight }.sorted() == [70, 72.5])
    }
}

@Suite("Резервная копия — идущая тренировка в файле")
struct BackupRunningWorkoutTests {
    @Test("остаётся идущей, если здесь ничего не идёт")
    func staysRunningWhenNothingRunsHere() throws {
        let source = try TestStore.open()
        let bench = Fixtures.exercise(in: source.context)
        let running = Fixtures.workout(date: Fixtures.day(1), startedAt: Fixtures.day(1), exercises: [bench], in: source.context)
        running.logSet(weight: 60, reps: 8, for: bench, now: Fixtures.day(1).addingTimeInterval(60), context: source.context)
        let file = try BackupExporter.makeFile(context: source.context)
        let target = try TestStore.open()

        let preview = try BackupImporter.preview(file, context: target.context)
        try BackupImporter.apply(file, context: target.context)

        #expect(!preview.activeBecomesCompleted)
        #expect(try target.fetch(Workout.self).first?.isActive == true)
    }

    @Test("становится завершённой в момент последнего подхода, если здесь уже идёт другая")
    func becomesCompletedWhenAnotherRunsHere() throws {
        let source = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: source.context)
        let running = Fixtures.workout(date: Fixtures.day(1), name: "Из файла", startedAt: Fixtures.day(1), exercises: [bench], in: source.context)
        let lastSetAt = Fixtures.day(1).addingTimeInterval(120)
        running.logSet(weight: 60, reps: 8, for: bench, now: Fixtures.day(1).addingTimeInterval(60), context: source.context)
        running.logSet(weight: 60, reps: 8, for: bench, now: lastSetAt, context: source.context)
        let file = try BackupExporter.makeFile(context: source.context)

        let target = try TestStore.open()
        let localExercise = Fixtures.exercise("Присед", in: target.context)
        Fixtures.workout(date: Fixtures.day(5), name: "Здесь", startedAt: Fixtures.day(5), exercises: [localExercise], in: target.context)

        let preview = try BackupImporter.preview(file, context: target.context)
        try BackupImporter.apply(file, context: target.context)

        let imported = try #require(try target.fetch(Workout.self).first { $0.name == "Из файла" })
        #expect(preview.activeBecomesCompleted)
        #expect(imported.completedAt == lastSetAt)
        #expect(try target.fetch(Workout.self).filter(\.isActive).map(\.name) == ["Здесь"])
    }
}

@Suite("Резервная копия — ошибочные файлы")
struct BackupDecodingTests {
    @Test("файл более новой версии формата отвергается явной ошибкой")
    func newerFormatIsRejected() throws {
        let data = Data(#"{"formatVersion": 99, "exportedAt": "2025-01-01T00:00:00.000Z"}"#.utf8)

        #expect(throws: BackupError.newerFormat(99)) {
            try BackupImporter.decode(data)
        }
    }

    @Test("чужой или повреждённый файл отвергается как нечитаемый", arguments: [
        "not json at all",
        #"{"hello": "world"}"#,
        #"{"formatVersion": 1, "exercises": "oops"}"#,
    ])
    func unreadableFileIsRejected(contents: String) throws {
        #expect(throws: BackupError.unreadable) {
            try BackupImporter.decode(Data(contents.utf8))
        }
    }

    @Test("дата без миллисекунд из отредактированного вручную файла читается")
    func dateWithoutMillisecondsDecodes() throws {
        let json = #"{"formatVersion":1,"exportedAt":"2025-01-01T00:00:00Z","exercises":[],"workouts":[],"standaloneSets":[]}"#

        let file = try BackupImporter.decode(Data(json.utf8))

        #expect(file.exportedAt == Fixtures.epoch)
    }
}

@Suite("Резервная копия — CSV")
struct BackupCSVTests {
    @Test("BOM, заголовок, десятичная запятая, номер подхода внутри упражнения")
    func rowsAndFormatting() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        Fixtures.completedWorkout(bench, sets: [(82.5, 5), (80, 6)], on: Fixtures.epoch, name: "Грудь", in: store.context)

        let csv = BackupExporter.csv(from: try BackupExporter.makeFile(context: store.context), timeZone: TimeZone(identifier: "UTC")!)
        let lines = csv.dropFirst().components(separatedBy: "\r\n")

        #expect(csv.hasPrefix("\u{FEFF}Дата;Время;Тренировка;Упражнение;Подход;Вес, кг;Повторы\r\n"))
        #expect(lines[1] == "01.01.2025;00:01;Грудь;Жим лёжа;1;82,5;5")
        #expect(lines[2] == "01.01.2025;00:02;Грудь;Жим лёжа;2;80;6")
    }

    @Test("поля с разделителем и кавычками экранируются")
    func fieldsAreEscaped() {
        #expect(BackupExporter.csvField(#"Грудь; "тяжёлая""#) == #""Грудь; ""тяжёлая""""#)
        #expect(BackupExporter.csvField("Спина") == "Спина")
        #expect(BackupExporter.csvField("две\nстроки") == "\"две\nстроки\"")
    }

    @Test("подходы вне тренировки идут в конце с пометкой")
    func standaloneSetsGoLast() throws {
        let store = try TestStore.open()
        let bench = Fixtures.exercise("Жим лёжа", in: store.context)
        Fixtures.standaloneSet(weight: 70, reps: 3, for: bench, at: Fixtures.epoch, in: store.context)
        Fixtures.completedWorkout(bench, sets: [(60, 8)], on: Fixtures.day(1), in: store.context)

        let csv = BackupExporter.csv(from: try BackupExporter.makeFile(context: store.context), timeZone: TimeZone(identifier: "UTC")!)
        let rows = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }

        #expect(rows.count == 3)
        #expect(rows[1].contains(";Тренировка;"))
        #expect(rows[2].contains(";Вне тренировки;"))
    }

    @Test("имя файла — местная дата")
    func fileNameUsesLocalDate() {
        let lateEvening = Fixtures.epoch.addingTimeInterval(-3_600) // 31 Dec 23:00 UTC
        #expect(BackupExporter.fileName(.json, date: lateEvening, timeZone: TimeZone(identifier: "Europe/Moscow")!) == "LiftLog-2025-01-01.json")
        #expect(BackupExporter.fileName(.csv, date: lateEvening, timeZone: TimeZone(identifier: "UTC")!) == "LiftLog-sets-2024-12-31.csv")
    }
}
