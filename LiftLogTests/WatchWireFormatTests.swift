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

@Suite("Совместимость со сборкой другой версии")
struct WatchWireFormatForwardCompatibilityTests {
    /// Часы и телефон обновляются независимо, и упавший декод контекста не виден
    /// пользователю никак: экран просто остаётся на последнем состоянии, которое
    /// удалось прочитать. Поэтому поля, добавленные позже, обязаны декодироваться
    /// пустыми, а не ронять весь контекст.
    @Test("контекст без version и plannedSets декодируется целиком, а не отбрасывается")
    func payloadWithoutLaterFieldsStillDecodes() throws {
        let workoutID = UUID()
        let planID = UUID()
        let exerciseID = UUID()
        let payload: [String: Any] = [
            "snapshot": [
                "workoutID": workoutID.uuidString,
                "name": "Тренировка",
                "date": 0,
                "exercises": [[
                    "id": exerciseID.uuidString,
                    "name": "Жим лёжа",
                    "setsLoggedCount": 2,
                ]],
            ],
            "plans": [[
                "id": planID.uuidString,
                "name": "План",
                "date": 0,
                "exercises": [],
            ]],
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONDecoder().decode(WatchContext.self, from: data)

        #expect(decoded.snapshot?.workoutID == workoutID)
        #expect(decoded.snapshot?.version == 0)
        #expect(decoded.snapshot?.exercises.first?.id == exerciseID)
        #expect(decoded.snapshot?.exercises.first?.plannedSets.isEmpty == true)
        #expect(decoded.plans.map(\.id) == [planID])
        #expect(decoded.plans.first?.version == 0)
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

@Suite("ExerciseInfo — счётчики подходов (FR-1)")
struct WatchWireFormatSetCounterTests {
    @Test(
        "ожидание считается по plannedSets, а остаток не уходит в минус",
        arguments: [
            (setsLoggedCount: 0, plannedCount: 3, expectedRemaining: 3, expectedFulfilled: false),
            (setsLoggedCount: 3, plannedCount: 3, expectedRemaining: 0, expectedFulfilled: true),
            (setsLoggedCount: 4, plannedCount: 3, expectedRemaining: 0, expectedFulfilled: true),
        ]
    )
    func remainingAndFulfilledFromPlannedSets(case: (setsLoggedCount: Int, plannedCount: Int, expectedRemaining: Int, expectedFulfilled: Bool)) throws {
        let info = WatchSyncFixtures.exerciseInfo(
            setsLoggedCount: `case`.setsLoggedCount,
            plannedSets: WatchSyncFixtures.plannedSets(Array(repeating: (weight: 60.0, reps: 8), count: `case`.plannedCount))
        )

        #expect(info.plannedSetCount == `case`.plannedCount)
        #expect(info.remainingSetCount == `case`.expectedRemaining)
        #expect(info.isSetPlanFulfilled == `case`.expectedFulfilled)
    }

    @Test("упражнение без плановых позиций не считается закрытым, даже с залогированными подходами")
    func noPlanIsNeverFulfilled() throws {
        let info = WatchSyncFixtures.exerciseInfo(setsLoggedCount: 1, plannedSets: [])

        #expect(info.plannedSetCount == 0)
        #expect(info.remainingSetCount == 0)
        #expect(info.isSetPlanFulfilled == false)
    }

    @Test("счётчики переживают round-trip провода")
    func countersSurviveRoundTrip() throws {
        let snapshot = WatchSyncFixtures.snapshot(
            exercises: [WatchSyncFixtures.exerciseInfo(
                setsLoggedCount: 2,
                plannedSets: WatchSyncFixtures.plannedSets([(60, 8), (60, 8), (65, 6)])
            )]
        )

        let decoded = try #require(try WatchSyncFixtures.roundTrip(snapshot))
        let info = try #require(decoded.exercises.first)

        #expect(info.plannedSetCount == 3)
        #expect(info.remainingSetCount == 1)
        #expect(info.isSetPlanFulfilled == false)
    }
}

@Suite("Планы, версия и конверт команд на проводе")
struct WatchWireFormatCommandTests {
    @Test("контекст с планами переживает round-trip целиком: версия, план подходов, подтверждения")
    func contextWithPlansRoundTrips() throws {
        let commandID = UUID()
        let plan = WatchSyncFixtures.summary(
            name: "Грудь",
            date: Fixtures.date(offset: 600),
            version: 4,
            exercises: [WatchSyncFixtures.exerciseInfo(
                name: "Жим лёжа",
                plannedSets: WatchSyncFixtures.plannedSets([(60, 8), (nil, 12)])
            )]
        )
        let context = WatchSyncFixtures.context(
            snapshot: WatchSyncFixtures.snapshot(name: "Идёт", version: 7),
            plans: [plan],
            appliedCommandIDs: [commandID]
        )

        let decoded = try WatchSyncFixtures.roundTrip(context)

        #expect(decoded.snapshot?.version == 7)
        #expect(decoded.snapshot?.name == "Идёт")
        #expect(decoded.plans.map(\.id) == [plan.id])
        #expect(decoded.plans.first?.version == 4)
        #expect(decoded.plans.first?.date == Fixtures.date(offset: 600))
        #expect(decoded.plans.first?.exercises.first?.plannedSets.map(\.weight) == [60, nil])
        #expect(decoded.plans.first?.exercises.first?.plannedSets.map(\.reps) == [8, 12])
        #expect(decoded.appliedCommandIDs == [commandID])
    }

    @Test("каждый вид команды переживает round-trip и сохраняет свой commandID", arguments: [0, 1, 2])
    func everyCommandKindRoundTrips(kind: Int) throws {
        let commandID = UUID()
        let workoutID = UUID()
        let command: WatchCommand = switch kind {
        case 0: .logSet(WatchSyncFixtures.logSetCommand(workoutID: workoutID, exerciseID: UUID(), commandID: commandID))
        case 1: .start(WatchSyncFixtures.startCommand(workoutID: workoutID, commandID: commandID))
        default: .finish(WatchSyncFixtures.finishCommand(workoutID: workoutID, commandID: commandID))
        }

        let data = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(WatchCommand.self, from: data)

        #expect(decoded.commandID == commandID)
        #expect(decoded.workoutID == workoutID)
    }

    @Test("очередь часов сериализуется вместе с ожидаемой версией")
    func pendingQueueRoundTrips() throws {
        let entry = WatchSyncFixtures.pending(
            .logSet(WatchSyncFixtures.logSetCommand(workoutID: UUID(), exerciseID: UUID())),
            expectedVersion: 9
        )

        let data = try JSONEncoder().encode([entry])
        let decoded = try JSONDecoder().decode([WatchPendingCommand].self, from: data)

        #expect(decoded.first?.expectedVersion == 9)
        #expect(decoded.first?.id == entry.id)
        #expect(decoded.first?.queuedAt == entry.queuedAt)
    }

    @Test("сохранённая очередь без queuedAt (запись прошлой сборки) читается, а не выбрасывается вместе с неотправленными подходами")
    func persistedQueueWithoutQueuedAtStillDecodes() throws {
        let json = """
        [{
            "expectedVersion": 2,
            "command": { "logSet": { "_0": {
                "commandID": "\(UUID().uuidString)",
                "workoutID": "\(UUID().uuidString)",
                "exerciseID": "\(UUID().uuidString)",
                "exerciseName": "Жим лёжа",
                "weight": 60,
                "reps": 8
            }}}
        }]
        """

        let decoded = try JSONDecoder().decode([WatchPendingCommand].self, from: Data(json.utf8))

        #expect(decoded.count == 1)
        #expect(decoded.first?.expectedVersion == 2)
    }
}

@Suite("Обратная совместимость: JSON без нового поля")
struct WatchWireFormatBackwardCompatibilityTests {
    @Test("контекст без plans/appliedCommandIDs (старая версия телефона) декодируется как пустые списки, а не падает")
    func contextWithoutNewKeysStillDecodes() throws {
        let json = """
        {
            "snapshot": {
                "workoutID": "\(UUID().uuidString)",
                "name": "",
                "date": 0,
                "version": 0,
                "exercises": [],
                "restEndDate": null,
                "restExerciseName": null
            }
        }
        """

        let decoded = try JSONDecoder().decode(WatchContext.self, from: Data(json.utf8))

        #expect(decoded.snapshot != nil)
        #expect(decoded.plans.isEmpty)
        #expect(decoded.appliedCommandIDs.isEmpty)
    }

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
