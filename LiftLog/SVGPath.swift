import SwiftUI

/// Minimal parser for the SVG path commands present in MuscleMapData
/// (M/L/C/Q/A/Z, absolute and relative). Converts a `d` attribute string
/// into a SwiftUI `Path`, approximating elliptical arcs with cubic beziers.
enum SVGPath {
    static func path(from d: String) -> Path {
        var path = Path()
        var scanner = PathScanner(d)
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var command: Character?

        parseLoop: while true {
            scanner.skipSeparators()
            if let letter = scanner.readCommandLetter() {
                command = letter
            }
            guard let c = command, !scanner.isAtEnd || "MmLlCcQqAaZz".contains(c) else { break }

            switch c {
            case "M", "m":
                guard let x = scanner.readNumber(), let y = scanner.readNumber() else { break parseLoop }
                let point = c == "m" ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.move(to: point)
                current = point
                subpathStart = point
                command = c == "m" ? "l" : "L"

            case "L", "l":
                guard let x = scanner.readNumber(), let y = scanner.readNumber() else { break parseLoop }
                let point = c == "l" ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addLine(to: point)
                current = point

            case "C", "c":
                guard let x1 = scanner.readNumber(), let y1 = scanner.readNumber(),
                      let x2 = scanner.readNumber(), let y2 = scanner.readNumber(),
                      let x = scanner.readNumber(), let y = scanner.readNumber()
                else { break parseLoop }
                let rel = c == "c"
                let c1 = rel ? CGPoint(x: current.x + x1, y: current.y + y1) : CGPoint(x: x1, y: y1)
                let c2 = rel ? CGPoint(x: current.x + x2, y: current.y + y2) : CGPoint(x: x2, y: y2)
                let end = rel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end

            case "Q", "q":
                guard let x1 = scanner.readNumber(), let y1 = scanner.readNumber(),
                      let x = scanner.readNumber(), let y = scanner.readNumber()
                else { break parseLoop }
                let rel = c == "q"
                let cp = rel ? CGPoint(x: current.x + x1, y: current.y + y1) : CGPoint(x: x1, y: y1)
                let end = rel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addQuadCurve(to: end, control: cp)
                current = end

            case "A", "a":
                guard let rx = scanner.readNumber(), let ry = scanner.readNumber(),
                      let rotation = scanner.readNumber(),
                      let largeArc = scanner.readFlag(),
                      let sweep = scanner.readFlag(),
                      let x = scanner.readNumber(), let y = scanner.readNumber()
                else { break parseLoop }
                let rel = c == "a"
                let end = rel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                for segment in arcSegments(from: current, rx: rx, ry: ry, rotationDegrees: rotation, largeArc: largeArc, sweep: sweep, to: end) {
                    path.addCurve(to: segment.end, control1: segment.c1, control2: segment.c2)
                }
                current = end

            case "Z", "z":
                path.closeSubpath()
                current = subpathStart

            default:
                break parseLoop
            }

            if scanner.isAtEnd { break }
        }

        return path
    }

    static func path(from strings: [String]) -> Path {
        var combined = Path()
        for d in strings {
            combined.addPath(path(from: d))
        }
        return combined
    }

    // MARK: - Elliptical arc -> cubic bezier segments (SVG spec Appendix F.6 / the standard "a2c" algorithm)

    private struct ArcBezierSegment {
        let c1: CGPoint
        let c2: CGPoint
        let end: CGPoint
    }

    private static func arcSegments(
        from p0: CGPoint, rx rxIn: Double, ry ryIn: Double,
        rotationDegrees: Double, largeArc: Bool, sweep: Bool, to p1: CGPoint
    ) -> [ArcBezierSegment] {
        let x1 = Double(p0.x), y1 = Double(p0.y)
        let x2 = Double(p1.x), y2 = Double(p1.y)
        if x1 == x2 && y1 == y2 { return [] }

        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 {
            // Degenerate radius: a cubic with control points on the chord renders as a straight line.
            let c1 = CGPoint(x: p0.x + (p1.x - p0.x) / 3, y: p0.y + (p1.y - p0.y) / 3)
            let c2 = CGPoint(x: p0.x + 2 * (p1.x - p0.x) / 3, y: p0.y + 2 * (p1.y - p0.y) / 3)
            return [ArcBezierSegment(c1: c1, c2: c2, end: p1)]
        }

        let phi = rotationDegrees * .pi / 180
        let sinPhi = sin(phi), cosPhi = cos(phi)

        let x1p = cosPhi * (x1 - x2) / 2 + sinPhi * (y1 - y2) / 2
        let y1p = -sinPhi * (x1 - x2) / 2 + cosPhi * (y1 - y2) / 2
        if x1p == 0 && y1p == 0 { return [] }

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let root = sqrt(lambda)
            rx *= root
            ry *= root
        }

        let rxSq = rx * rx, rySq = ry * ry, x1pSq = x1p * x1p, y1pSq = y1p * y1p
        var radicant = (rxSq * rySq) - (rxSq * y1pSq) - (rySq * x1pSq)
        if radicant < 0 { radicant = 0 }
        radicant /= (rxSq * y1pSq) + (rySq * x1pSq)
        radicant = sqrt(radicant) * ((largeArc == sweep) ? -1 : 1)

        let cxp = radicant * rx / ry * y1p
        let cyp = radicant * -ry / rx * x1p

        let cx = cosPhi * cxp - sinPhi * cyp + (x1 + x2) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (y1 + y2) / 2

        func unitVectorAngle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let sign: Double = (ux * vy - uy * vx < 0) ? -1 : 1
            var dot = ux * vx + uy * vy
            dot = min(1, max(-1, dot))
            return sign * acos(dot)
        }

        let v1x = (x1p - cxp) / rx, v1y = (y1p - cyp) / ry
        let v2x = (-x1p - cxp) / rx, v2y = (-y1p - cyp) / ry
        let theta1 = unitVectorAngle(1, 0, v1x, v1y)
        var deltaTheta = unitVectorAngle(v1x, v1y, v2x, v2y)
        if !sweep && deltaTheta > 0 { deltaTheta -= 2 * .pi }
        if sweep && deltaTheta < 0 { deltaTheta += 2 * .pi }

        let segmentCount = max(Int(ceil(abs(deltaTheta) / (.pi / 2))), 1)
        let delta = deltaTheta / Double(segmentCount)
        let alpha = 4.0 / 3.0 * tan(delta / 4)

        var theta = theta1
        var result: [ArcBezierSegment] = []
        for _ in 0..<segmentCount {
            let theta2 = theta + delta
            let ux1 = cos(theta), uy1 = sin(theta)
            let ux2 = cos(theta2), uy2 = sin(theta2)

            let uc1x = ux1 - uy1 * alpha, uc1y = uy1 + ux1 * alpha
            let uc2x = ux2 + uy2 * alpha, uc2y = uy2 - ux2 * alpha

            func transform(_ ux: Double, _ uy: Double) -> CGPoint {
                CGPoint(
                    x: cosPhi * ux * rx - sinPhi * uy * ry + cx,
                    y: sinPhi * ux * rx + cosPhi * uy * ry + cy
                )
            }

            result.append(ArcBezierSegment(c1: transform(uc1x, uc1y), c2: transform(uc2x, uc2y), end: transform(ux2, uy2)))
            theta = theta2
        }
        return result
    }
}

/// Character-cursor scanner implementing SVG path number/flag grammar, including
/// separator-less packed numbers (".43.42") and single-digit arc flags ("01").
private struct PathScanner {
    private let chars: [Character]
    private var index = 0

    init(_ string: String) {
        chars = Array(string)
    }

    var isAtEnd: Bool { index >= chars.count }

    private func peek() -> Character? { isAtEnd ? nil : chars[index] }

    @discardableResult
    private mutating func advance() -> Character {
        defer { index += 1 }
        return chars[index]
    }

    mutating func skipSeparators() {
        while let ch = peek(), ch == " " || ch == "\t" || ch == "\n" || ch == "\r" || ch == "," {
            index += 1
        }
    }

    mutating func readCommandLetter() -> Character? {
        guard let ch = peek(), ch.isLetter else { return nil }
        advance()
        return ch
    }

    mutating func readNumber() -> Double? {
        skipSeparators()
        guard !isAtEnd else { return nil }
        var text = ""
        if let sign = peek(), sign == "-" || sign == "+" {
            text.append(advance())
        }
        var sawDot = false
        var sawDigit = false
        while let ch = peek() {
            if ch.isNumber {
                text.append(advance())
                sawDigit = true
            } else if ch == "." && !sawDot {
                sawDot = true
                text.append(advance())
            } else if ch == "e" || ch == "E" {
                text.append(advance())
                if let sign = peek(), sign == "-" || sign == "+" { text.append(advance()) }
                while let d = peek(), d.isNumber { text.append(advance()) }
            } else {
                break
            }
        }
        guard sawDigit, let value = Double(text) else { return nil }
        return value
    }

    mutating func readFlag() -> Bool? {
        skipSeparators()
        guard let ch = peek() else { return nil }
        advance()
        if ch == "0" { return false }
        if ch == "1" { return true }
        return nil
    }
}
