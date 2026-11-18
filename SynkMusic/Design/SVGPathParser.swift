import CoreGraphics
import Foundation

// Minimal SVG path "d" parser -> CGPath. Supports M/m L/l H/h V/v C/c S/s Q/q
// T/t A/a Z/z, which covers the heroicons set used by SYNK.
enum SVGPathParser {
    static func parse(_ d: String) -> CGPath {
        let path = CGMutablePath()
        var scanner = PathScanner(d)

        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint? = nil
        var lastCommand: Character = " "

        func reflect(_ c: CGPoint?, about p: CGPoint) -> CGPoint {
            guard let c = c else { return p }
            return CGPoint(x: 2 * p.x - c.x, y: 2 * p.y - c.y)
        }

        while let cmd = scanner.nextCommand() {
            let isRel = cmd.isLowercase
            let C = Character(cmd.uppercased())
            let prevCommand = lastCommand
            lastCommand = cmd

            switch C {
            case "M":
                guard let x = scanner.nextNumber(), let y = scanner.nextNumber() else { break }
                current = isRel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.move(to: current)
                start = current
                // Subsequent implicit pairs are treated as line-to.
                while scanner.peekIsNumber() {
                    guard let lx = scanner.nextNumber(), let ly = scanner.nextNumber() else { break }
                    current = isRel ? CGPoint(x: current.x + lx, y: current.y + ly) : CGPoint(x: lx, y: ly)
                    path.addLine(to: current)
                }
                lastControl = nil
            case "L":
                while scanner.peekIsNumber() {
                    guard let x = scanner.nextNumber(), let y = scanner.nextNumber() else { break }
                    current = isRel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                    path.addLine(to: current)
                }
                lastControl = nil
            case "H":
                while scanner.peekIsNumber() {
                    guard let x = scanner.nextNumber() else { break }
                    current = isRel ? CGPoint(x: current.x + x, y: current.y) : CGPoint(x: x, y: current.y)
                    path.addLine(to: current)
                }
                lastControl = nil
            case "V":
                while scanner.peekIsNumber() {
                    guard let y = scanner.nextNumber() else { break }
                    current = isRel ? CGPoint(x: current.x, y: current.y + y) : CGPoint(x: current.x, y: y)
                    path.addLine(to: current)
                }
                lastControl = nil
            case "C":
                while scanner.peekIsNumber() {
                    guard let x1 = scanner.nextNumber(), let y1 = scanner.nextNumber(),
                          let x2 = scanner.nextNumber(), let y2 = scanner.nextNumber(),
                          let x = scanner.nextNumber(), let y = scanner.nextNumber() else { break }
                    let c1 = isRel ? CGPoint(x: current.x + x1, y: current.y + y1) : CGPoint(x: x1, y: y1)
                    let c2 = isRel ? CGPoint(x: current.x + x2, y: current.y + y2) : CGPoint(x: x2, y: y2)
                    let end = isRel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                    path.addCurve(to: end, control1: c1, control2: c2)
                    current = end
                    lastControl = c2
                }
            case "S":
                while scanner.peekIsNumber() {
                    guard let x2 = scanner.nextNumber(), let y2 = scanner.nextNumber(),
                          let x = scanner.nextNumber(), let y = scanner.nextNumber() else { break }
                    let c1 = (prevCommand == "C" || prevCommand == "c" || prevCommand == "S" || prevCommand == "s")
                        ? reflect(lastControl, about: current) : current
                    let c2 = isRel ? CGPoint(x: current.x + x2, y: current.y + y2) : CGPoint(x: x2, y: y2)
                    let end = isRel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                    path.addCurve(to: end, control1: c1, control2: c2)
                    current = end
                    lastControl = c2
                }
            case "Q":
                while scanner.peekIsNumber() {
                    guard let x1 = scanner.nextNumber(), let y1 = scanner.nextNumber(),
                          let x = scanner.nextNumber(), let y = scanner.nextNumber() else { break }
                    let c1 = isRel ? CGPoint(x: current.x + x1, y: current.y + y1) : CGPoint(x: x1, y: y1)
                    let end = isRel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                    path.addQuadCurve(to: end, control: c1)
                    current = end
                    lastControl = c1
                }
            case "T":
                while scanner.peekIsNumber() {
                    guard let x = scanner.nextNumber(), let y = scanner.nextNumber() else { break }
                    let c1 = (prevCommand == "Q" || prevCommand == "q" || prevCommand == "T" || prevCommand == "t")
                        ? reflect(lastControl, about: current) : current
                    let end = isRel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                    path.addQuadCurve(to: end, control: c1)
                    current = end
                    lastControl = c1
                }
            case "A":
                while scanner.peekIsNumber() {
                    guard let rx = scanner.nextNumber(), let ry = scanner.nextNumber(),
                          let rot = scanner.nextNumber(), let laf = scanner.nextFlag(),
                          let sf = scanner.nextFlag(), let x = scanner.nextNumber(),
                          let y = scanner.nextNumber() else { break }
                    let end = isRel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                    addArc(path, from: current, to: end, rx: rx, ry: ry,
                           xRot: rot, largeArc: laf != 0, sweep: sf != 0)
                    current = end
                    lastControl = nil
                }
            case "Z":
                path.closeSubpath()
                current = start
                lastControl = nil
            default:
                break
            }
        }
        return path
    }

    // Endpoint -> center arc conversion (per SVG spec appendix), then add to path.
    private static func addArc(_ path: CGMutablePath, from p0: CGPoint, to p1: CGPoint,
                               rx: CGFloat, ry: CGFloat, xRot: CGFloat,
                               largeArc: Bool, sweep: Bool) {
        var rx = abs(rx), ry = abs(ry)
        if rx == 0 || ry == 0 { path.addLine(to: p1); return }

        let phi = xRot * .pi / 180
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cos(phi) * dx + sin(phi) * dy
        let y1p = -sin(phi) * dx + cos(phi) * dy

        var lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { let s = sqrt(lambda); rx *= s; ry *= s; lambda = 1 }

        let sign: CGFloat = (largeArc != sweep) ? 1 : -1
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let co = sign * sqrt(max(0, num / den))
        let cxp = co * (rx * y1p / ry)
        let cyp = co * -(ry * x1p / rx)

        let cx = cos(phi) * cxp - sin(phi) * cyp + (p0.x + p1.x) / 2
        let cy = sin(phi) * cxp + cos(phi) * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            var a = acos(min(1, max(-1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var dTheta = angle((x1p - cxp) / rx, (y1p - cyp) / ry,
                           (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && dTheta > 0 { dTheta -= 2 * .pi }
        if sweep && dTheta < 0 { dTheta += 2 * .pi }

        // Approximate the arc with cubic segments.
        let segments = max(1, Int(ceil(abs(dTheta) / (.pi / 2))))
        let delta = dTheta / CGFloat(segments)
        let t = 8.0 / 3.0 * sin(delta / 4) * sin(delta / 4) / sin(delta / 2)

        var angleStart = theta1
        var prev = p0
        for _ in 0..<segments {
            let angleEnd = angleStart + delta
            let cosS = cos(angleStart), sinS = sin(angleStart)
            let cosE = cos(angleEnd), sinE = sin(angleEnd)

            func point(_ a: CGFloat) -> CGPoint {
                let x = cos(phi) * rx * cos(a) - sin(phi) * ry * sin(a) + cx
                let y = sin(phi) * rx * cos(a) + cos(phi) * ry * sin(a) + cy
                return CGPoint(x: x, y: y)
            }
            let end = point(angleEnd)
            let c1 = CGPoint(
                x: prev.x + t * (-cos(phi) * rx * sinS - sin(phi) * ry * cosS),
                y: prev.y + t * (-sin(phi) * rx * sinS + cos(phi) * ry * cosS)
            )
            let c2 = CGPoint(
                x: end.x + t * (cos(phi) * rx * sinE + sin(phi) * ry * cosE),
                y: end.y + t * (sin(phi) * rx * sinE - cos(phi) * ry * cosE)
            )
            path.addCurve(to: end, control1: c1, control2: c2)
            prev = end
            angleStart = angleEnd
        }
    }
}

// Lightweight character scanner tuned for SVG path syntax.
private struct PathScanner {
    private let chars: [Character]
    private var i = 0
    init(_ s: String) { chars = Array(s) }

    private mutating func skipSep() {
        while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t" {
            i += 1
        }
    }

    mutating func nextCommand() -> Character? {
        skipSep()
        guard i < chars.count else { return nil }
        let c = chars[i]
        if c.isLetter { i += 1; return c }
        return nil
    }

    mutating func peekIsNumber() -> Bool {
        var j = i
        while j < chars.count, chars[j] == " " || chars[j] == "," || chars[j] == "\n" || chars[j] == "\t" { j += 1 }
        guard j < chars.count else { return false }
        let c = chars[j]
        return c.isNumber || c == "-" || c == "+" || c == "."
    }

    mutating func nextNumber() -> CGFloat? {
        skipSep()
        guard i < chars.count else { return nil }
        var s = ""
        if chars[i] == "-" || chars[i] == "+" { s.append(chars[i]); i += 1 }
        var seenDot = false, seenExp = false
        while i < chars.count {
            let c = chars[i]
            if c.isNumber { s.append(c); i += 1 }
            else if c == "." && !seenDot && !seenExp { seenDot = true; s.append(c); i += 1 }
            else if (c == "e" || c == "E") && !seenExp {
                seenExp = true; s.append(c); i += 1
                if i < chars.count, chars[i] == "-" || chars[i] == "+" { s.append(chars[i]); i += 1 }
            } else { break }
        }
        return Double(s).map { CGFloat($0) }
    }

    // Arc flags may be a single "0"/"1" with no separator (e.g. "0 0").
    mutating func nextFlag() -> Int? {
        skipSep()
        guard i < chars.count else { return nil }
        let c = chars[i]
        if c == "0" { i += 1; return 0 }
        if c == "1" { i += 1; return 1 }
        return nextNumber().map { Int($0) }
    }
}
