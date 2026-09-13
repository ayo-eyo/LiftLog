import Testing
import Foundation
@testable import LiftLog

@Suite("RestTimer")
struct RestTimerTests {
    @Test("start выставляет endDate относительно переданного now и запоминает имя упражнения")
    func startSetsEndDateAndExerciseName() {
        let timer = Fixtures.restTimer()
        let now = Fixtures.date(offset: 0)

        timer.start(duration: 90, exerciseName: "Жим лёжа", now: now)

        #expect(timer.endDate == now.addingTimeInterval(90))
        #expect(timer.exerciseName == "Жим лёжа")
    }

    @Test("remaining(at:) отдаёт оставшееся время в середине интервала")
    func remainingMidInterval() {
        let timer = Fixtures.restTimer()
        let now = Fixtures.date(offset: 0)
        timer.start(duration: 100, exerciseName: "Присед", now: now)

        #expect(timer.remaining(at: now.addingTimeInterval(40)) == 60)
    }

    @Test("remaining(at:) равен нулю ровно в момент окончания")
    func remainingAtExactEnd() {
        let timer = Fixtures.restTimer()
        let now = Fixtures.date(offset: 0)
        timer.start(duration: 100, exerciseName: "Присед", now: now)

        #expect(timer.remaining(at: now.addingTimeInterval(100)) == 0)
    }

    @Test("remaining(at:) не уходит в минус после окончания")
    func remainingAfterEndIsClampedToZero() {
        let timer = Fixtures.restTimer()
        let now = Fixtures.date(offset: 0)
        timer.start(duration: 100, exerciseName: "Присед", now: now)

        #expect(timer.remaining(at: now.addingTimeInterval(150)) == 0)
    }

    @Test("remaining(at:) равен нулю без старта")
    func remainingWithoutStartIsZero() {
        let timer = Fixtures.restTimer()
        #expect(timer.remaining(at: Fixtures.date(offset: 0)) == 0)
    }

    @Test("isResting(at:) истинно до конца интервала")
    func isRestingBeforeEnd() {
        let timer = Fixtures.restTimer()
        let now = Fixtures.date(offset: 0)
        timer.start(duration: 100, exerciseName: "Присед", now: now)

        #expect(timer.isResting(at: now.addingTimeInterval(50)) == true)
    }

    @Test("isResting(at:) ложно на границе и после окончания")
    func isRestingFalseAtAndAfterEnd() {
        let timer = Fixtures.restTimer()
        let now = Fixtures.date(offset: 0)
        timer.start(duration: 100, exerciseName: "Присед", now: now)

        #expect(timer.isResting(at: now.addingTimeInterval(100)) == false)
        #expect(timer.isResting(at: now.addingTimeInterval(150)) == false)
    }

    @Test("skip обнуляет endDate, но не имя упражнения — accessoryText полагается на isResting")
    func skipClearsEndDateButKeepsExerciseName() {
        let timer = Fixtures.restTimer()
        timer.start(duration: 100, exerciseName: "Присед", now: Fixtures.date(offset: 0))

        timer.skip()

        #expect(timer.endDate == nil)
        #expect(timer.exerciseName == "Присед")
    }

    @Test("start планирует уведомление о конце отдыха, skip его отменяет")
    func startSchedulesNotificationSkipCancelsIt() {
        var scheduled: (duration: TimeInterval, name: String)?
        var cancelled = false
        let timer = RestTimer(
            scheduleNotification: { scheduled = ($0, $1) },
            cancelNotification: { cancelled = true }
        )

        timer.start(duration: 90, exerciseName: "Присед", now: Fixtures.date(offset: 0))
        #expect(scheduled?.duration == 90)
        #expect(scheduled?.name == "Присед")
        #expect(cancelled == false)

        timer.skip()
        #expect(cancelled == true)
    }

    @Test(
        "TimeInterval.clockString форматирует минуты:секунды",
        arguments: [
            (0.0, "0:00"),
            (5.0, "0:05"),
            (59.4, "0:59"),
            (59.6, "1:00"),
            (60.0, "1:00"),
            (125.0, "2:05"),
            (3600.0, "60:00"),
            (-5.0, "0:00"),
        ]
    )
    func clockStringFormatsCorrectly(seconds: TimeInterval, expected: String) {
        #expect(seconds.clockString == expected)
    }
}
