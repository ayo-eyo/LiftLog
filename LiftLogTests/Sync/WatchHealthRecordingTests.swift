import Testing
import Foundation
@testable import LiftLog

@Suite("WatchHealthRecording — когда часы пишут тренировку в Здоровье")
struct WatchHealthRecordingTests {
    @Test("появилась тренировка — запись начинается")
    func startsWhenWorkoutAppears() {
        let id = UUID()
        #expect(WatchHealthRecording.action(recording: nil, active: id, isTrusted: true) == .start(id))
    }

    @Test("тренировка ушла — запись заканчивается")
    func endsWhenWorkoutGoesAway() {
        #expect(WatchHealthRecording.action(recording: UUID(), active: nil, isTrusted: true) == .end)
    }

    @Test("та же тренировка — ничего не происходит")
    func sameWorkoutKeepsRecording() {
        let id = UUID()
        #expect(WatchHealthRecording.action(recording: id, active: id, isTrusted: true) == .none)
    }

    @Test("идёт другая тренировка — текущая запись закрывается и начинается новая")
    func differentWorkoutRestarts() {
        let next = UUID()
        #expect(WatchHealthRecording.action(recording: UUID(), active: next, isTrusted: true) == .restart(next))
    }

    @Test("по контексту из прошлого запуска запись не начинается и не обрывается")
    func untrustedContextChangesNothing() {
        #expect(WatchHealthRecording.action(recording: nil, active: UUID(), isTrusted: false) == .none)
        #expect(WatchHealthRecording.action(recording: UUID(), active: nil, isTrusted: false) == .none)
    }

    @Test("открыли часы посреди тренировки — длительность считается от её начала")
    func backdatesToWorkoutStart() {
        let now = Fixtures.date(offset: 3600)
        let start = WatchHealthRecording.collectionStart(workoutDate: Fixtures.epoch, startedLocally: false, now: now)
        #expect(start == Fixtures.epoch)
    }

    @Test("тренировка, начатая на часах офлайн, пишется с текущего момента — её дата ещё дата создания плана")
    func locallyStartedStartsNow() {
        let now = Fixtures.date(offset: 600)
        let start = WatchHealthRecording.collectionStart(workoutDate: Fixtures.epoch, startedLocally: true, now: now)
        #expect(start == now)
    }

    @Test("неправдоподобная дата начала (давно или в будущем) заменяется текущим моментом")
    func implausibleDateStartsNow() {
        let now = Fixtures.date(offset: WatchHealthRecording.maxBackdate + 1)
        #expect(WatchHealthRecording.collectionStart(workoutDate: Fixtures.epoch, startedLocally: false, now: now) == now)
        #expect(WatchHealthRecording.collectionStart(workoutDate: Fixtures.date(offset: 60), startedLocally: false, now: Fixtures.epoch) == Fixtures.epoch)
    }
}
