import Testing
import Foundation
@testable import LiftLog

@Suite("WatchContext/WatchWorkoutSnapshot — round-trip через провод")
struct WatchWireFormatRoundTripTests {
    @Test("все поля снапшота сохраняются при round-trip, включая nil restEndDate/restExerciseName")
    func roundTripPreservesAllFields() throws {
        let snapshot = WatchSyncFixtures.snapshot(
            exercises: [WatchSyncFixtures.exerciseInfo(name: "Жим лёжа", setsLoggedCount: 2, weight: 60, reps: 8)],
            restEndDate: Fixtures.date(offset: 120),
            restExerciseName: "Жим лёжа"
        )

        let decoded = try #require(try WatchSyncFixtures.roundTrip(snapshot))

        #expect(decoded.workoutID == snapshot.workoutID)
        #expect(decoded.restEndDate == snapshot.restEndDate)
        #expect(decoded.restExerciseName == snapshot.restExerciseName)
        #expect(decoded.exercises.map(\.name) == ["Жим лёжа"])
        #expect(decoded.exercises.first?.setsLoggedCount == 2)
        #expect(decoded.exercises.first?.weight == 60)
        #expect(decoded.exercises.first?.reps == 8)
    }

    @Test("nil restEndDate/restExerciseName и nil weight/reps в ExerciseInfo переживают round-trip как nil")
    func roundTripPreservesNilFields() throws {
        let snapshot = WatchSyncFixtures.snapshot(
            exercises: [WatchSyncFixtures.exerciseInfo(weight: nil, reps: nil)],
            restEndDate: nil,
            restExerciseName: nil
        )

        let decoded = try #require(try WatchSyncFixtures.roundTrip(snapshot))

        #expect(decoded.restEndDate == nil)
        #expect(decoded.restExerciseName == nil)
        #expect(decoded.exercises.first?.weight == nil)
        #expect(decoded.exercises.first?.reps == nil)
    }

    @Test("snapshot == nil (нет активной тренировки) переживает round-trip как nil, а не как отсутствие ключа")
    func nilSnapshotRoundTripsAsNil() throws {
        let decoded = try WatchSyncFixtures.roundTrip(nil)
        #expect(decoded == nil)
    }
}

@Suite("Совместимость по датам")
struct WatchWireFormatDateStrategyTests {
    @Test("даты кодируются и декодируются одной стратегией на обеих сторонах провода")
    func datesRoundTripWithMatchingStrategy() throws {
        // Mirrors exactly what WatchSessionManager.send / PhoneSessionManager.applyContext
        // do: plain JSONEncoder()/JSONDecoder() with no explicit date strategy override.
        // If either side added `.iso8601` without the other, this would fail to decode
        // (or silently decode a different instant).
        let restEndDate = Fixtures.date(offset: 42.5)
        let snapshot = WatchSyncFixtures.snapshot(restEndDate: restEndDate)

        let data = try JSONEncoder().encode(WatchContext(snapshot: snapshot))
        let decoded = try JSONDecoder().decode(WatchContext.self, from: data)

        #expect(decoded.snapshot?.restEndDate == restEndDate)
    }
}

@Suite("Обратная совместимость: JSON без нового поля")
struct WatchWireFormatBackwardCompatibilityTests {
    @Test("WatchLogSetCommand без commandID (старая версия часов) не декодируется — явный отказ, а не тихий дефолт")
    func missingCommandIDFailsToDecode() throws {
        let json = """
        {
            "workoutID": "\(UUID().uuidString)",
            "exerciseID": "\(UUID().uuidString)",
            "exerciseName": "Жим лёжа",
            "weight": 60,
            "reps": 8
        }
        """
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(WatchLogSetCommand.self, from: Data(json.utf8))
        }
    }
}

@Suite("Паритет копий WorkoutSyncModels.swift")
struct WatchWireFormatParityTests {
    @Test("LiftLog и LiftLogWatchApp Watch App копии WorkoutSyncModels.swift идентичны")
    func copiesAreIdentical() throws {
        let phone = try String(contentsOf: SourcePaths.phoneSyncModels, encoding: .utf8)
        let watch = try String(contentsOf: SourcePaths.watchSyncModels, encoding: .utf8)
        #expect(phone == watch)
    }
}

@Suite("Размер payload")
struct WatchWireFormatPayloadSizeTests {
    @Test("снапшот на 30 упражнений заметно меньше лимита updateApplicationContext")
    func thirtyExerciseSnapshotFitsUnderContextLimit() throws {
        // WCSession.updateApplicationContext silently fails/truncates well before this;
        // Apple doesn't publish an exact number, but real-world guidance is "a few KB is
        // fine, tens of KB is risky" — this asserts we're an order of magnitude under that.
        let exercises = (0..<30).map { index in
            WatchSyncFixtures.exerciseInfo(name: "Упражнение номер \(index) с длинным названием", setsLoggedCount: index, weight: 60, reps: 8)
        }
        let snapshot = WatchSyncFixtures.snapshot(exercises: exercises, restEndDate: Fixtures.date(offset: 0), restExerciseName: "Жим лёжа")

        let payload = try WatchSyncFixtures.applicationContext(snapshot)
        let data = try #require(payload["data"] as? Data)

        #expect(data.count < 16_384)
    }
}
