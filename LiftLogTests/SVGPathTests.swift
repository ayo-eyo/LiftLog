import Testing
import SwiftUI
@testable import LiftLog

private extension Path {
    var elements: [Path.Element] {
        var result: [Path.Element] = []
        forEach { result.append($0) }
        return result
    }
}

private func approxEqual(_ a: CGPoint, _ b: CGPoint, tolerance: CGFloat = 0.01) -> Bool {
    abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance
}

@Suite("SVGPath — базовые команды")
struct SVGPathBasicCommandTests {
    @Test("абсолютные M/L дают move и line в заданные точки")
    func absoluteMoveAndLine() {
        let elements = SVGPath.path(from: "M0 0 L10 10").elements
        #expect(elements.count == 2)
        guard case .move(let m) = elements[0], case .line(let l) = elements[1] else {
            Issue.record("неверные типы элементов: \(elements)")
            return
        }
        #expect(approxEqual(m, .zero))
        #expect(approxEqual(l, CGPoint(x: 10, y: 10)))
    }

    @Test("относительные m/l смещают точку от текущей позиции")
    func relativeMoveAndLine() {
        let elements = SVGPath.path(from: "M5 5 l10 10").elements
        guard case .move(let m) = elements[0], case .line(let l) = elements[1] else {
            Issue.record("неверные типы элементов: \(elements)")
            return
        }
        #expect(approxEqual(m, CGPoint(x: 5, y: 5)))
        #expect(approxEqual(l, CGPoint(x: 15, y: 15)))
    }

    @Test("неявный lineto после moveto (M x y x2 y2) трактуется как L")
    func implicitLinetoAfterAbsoluteMoveto() {
        let elements = SVGPath.path(from: "M0 0 10 10 20 0").elements
        #expect(elements.count == 3)
        guard case .move = elements[0], case .line(let l1) = elements[1], case .line(let l2) = elements[2] else {
            Issue.record("неверные типы элементов: \(elements)")
            return
        }
        #expect(approxEqual(l1, CGPoint(x: 10, y: 10)))
        #expect(approxEqual(l2, CGPoint(x: 20, y: 0)))
    }

    @Test("неявный lineto после относительного moveto (m x y x2 y2) трактуется как l")
    func implicitLinetoAfterRelativeMoveto() {
        let elements = SVGPath.path(from: "m5 5 5 5").elements
        guard case .move(let m) = elements[0], case .line(let l) = elements[1] else {
            Issue.record("неверные типы элементов: \(elements)")
            return
        }
        #expect(approxEqual(m, CGPoint(x: 5, y: 5)))
        #expect(approxEqual(l, CGPoint(x: 10, y: 10)))
    }

    @Test("Z замыкает подпуть, следующая команда начинается от начала подпути")
    func closeSubpathReturnsToStart() {
        let elements = SVGPath.path(from: "M0 0 L10 0 L10 10 Z L5 5").elements
        guard case .closeSubpath = elements[3], case .line(let afterClose) = elements[4] else {
            Issue.record("неверные типы элементов: \(elements)")
            return
        }
        // After Z, current point resets to the subpath start (0,0), so the following
        // line goes from (0,0) to (5,5) — its *end* point is what forEach exposes.
        #expect(approxEqual(afterClose, CGPoint(x: 5, y: 5)))
    }

    @Test("C — кубическая кривая")
    func cubicCurve() {
        let elements = SVGPath.path(from: "M0 0 C0 10 10 10 10 0").elements
        guard case .curve(let end, let c1, let c2) = elements[1] else {
            Issue.record("ожидался curve: \(elements)")
            return
        }
        #expect(approxEqual(end, CGPoint(x: 10, y: 0)))
        #expect(approxEqual(c1, CGPoint(x: 0, y: 10)))
        #expect(approxEqual(c2, CGPoint(x: 10, y: 10)))
    }

    @Test("Q — квадратичная кривая")
    func quadCurve() {
        let elements = SVGPath.path(from: "M0 0 Q5 10 10 0").elements
        guard case .quadCurve(let end, let control) = elements[1] else {
            Issue.record("ожидался quadCurve: \(elements)")
            return
        }
        #expect(approxEqual(end, CGPoint(x: 10, y: 0)))
        #expect(approxEqual(control, CGPoint(x: 5, y: 10)))
    }
}

@Suite("SVGPath — дуги (A)")
struct SVGPathArcTests {
    @Test("конечная точка дуги совпадает с заданной для обеих комбинаций large-arc/sweep")
    func arcEndpointMatchesForAllFlagCombinations() {
        for (largeArc, sweep) in [(0, 0), (0, 1), (1, 0), (1, 1)] {
            let d = "M0 0 A50 50 0 \(largeArc) \(sweep) 100 0"
            let elements = SVGPath.path(from: d).elements
            let end = elements.compactMap { element -> CGPoint? in
                if case .curve(let e, _, _) = element { return e }
                return nil
            }.last
            #expect(approxEqual(end ?? .zero, CGPoint(x: 100, y: 0)), "large-arc=\(largeArc) sweep=\(sweep) не дошла до конечной точки")
        }
    }
}

@Suite("SVGPath — разбор чисел")
struct SVGPathNumberParsingTests {
    @Test("запятые и пробелы как разделители")
    func commasAndSpacesAsSeparators() {
        let elements = SVGPath.path(from: "M0,0L10,10").elements
        guard case .line(let l) = elements[1] else {
            Issue.record("ожидался line: \(elements)")
            return
        }
        #expect(approxEqual(l, CGPoint(x: 10, y: 10)))
    }

    @Test("минус без разделителя (10-5) разбирается как два числа")
    func minusWithoutSeparator() {
        let elements = SVGPath.path(from: "M0 0 L10-5").elements
        guard case .line(let l) = elements[1] else {
            Issue.record("ожидался line: \(elements)")
            return
        }
        #expect(approxEqual(l, CGPoint(x: 10, y: -5)))
    }

    @Test("экспонента (1e2)")
    func exponentNotation() {
        let elements = SVGPath.path(from: "M0 0 L1e2 0").elements
        guard case .line(let l) = elements[1] else {
            Issue.record("ожидался line: \(elements)")
            return
        }
        #expect(approxEqual(l, CGPoint(x: 100, y: 0)))
    }

    @Test("ведущая точка (.5)")
    func leadingDot() {
        let elements = SVGPath.path(from: "M0 0 L.5 .25").elements
        guard case .line(let l) = elements[1] else {
            Issue.record("ожидался line: \(elements)")
            return
        }
        #expect(approxEqual(l, CGPoint(x: 0.5, y: 0.25)))
    }
}

@Suite("SVGPath — устойчивость к некорректному вводу")
struct SVGPathRobustnessTests {
    @Test("пустая строка даёт пустой Path")
    func emptyStringGivesEmptyPath() {
        #expect(SVGPath.path(from: "").isEmpty)
    }

    @Test("обрезанная команда завершается без краша и без зацикливания")
    func truncatedCommandDoesNotHangOrCrash() {
        let path = SVGPath.path(from: "M0 0 L10")
        #expect(path.elements.count == 1)
    }

    @Test("мусорный ввод завершается без краша и без зацикливания")
    func garbageInputDoesNotHangOrCrash() {
        let path = SVGPath.path(from: "!!!not a path??? M5 5")
        _ = path.elements
    }
}
