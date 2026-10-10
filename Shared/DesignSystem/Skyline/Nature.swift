import SwiftUI

// The mountains behind the city, the arcades in front of it, and the bull it is
// named for.

/// A tiny deterministic generator, so a "random" skyline is the same one every
/// time it is drawn: no flicker between frames, and the same city in a test.
struct SkylineRandom: Sendable {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(truncatingIfNeeded: seed) &* 6364136223846793005 &+ 1442695040888963407
        for _ in 0 ..< 3 { _ = next() }
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 33
    }

    /// A value in `range`.
    mutating func value(in range: ClosedRange<CGFloat>) -> CGFloat {
        range.lowerBound + CGFloat(next() % 10_000) / 10_000 * (range.upperBound - range.lowerBound)
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }
}

// MARK: - The Alps

/// A range of faceted peaks: a lit face, a shaded face and a snow cap on each, the
/// way the poster cuts the mountains.
struct AlpsDrawing: LandmarkDrawing {
    /// A long range for a screen edge; otherwise three peaks, for a rim mark.
    var wide = true
    /// Moves each peak a little, so two ranges on one screen are not twins.
    var seed = 1

    static let box = CGSize(width: 200, height: 100)
    var boxSize: CGSize { wide ? Self.box : CGSize(width: 100, height: 100) }

    func draw(_ d: inout Draw, _ p: SkylinePalette) {
        var rng = SkylineRandom(seed: seed)
        // x centre, height as a fraction of the box, half-width. Back row first, so
        // the front peaks overlap them.
        let back: [(x: CGFloat, h: CGFloat, half: CGFloat)] = wide
            ? [(30, 0.92, 38), (78, 0.74, 34), (118, 1.0, 40), (160, 0.82, 36), (188, 0.6, 28)]
            : [(26, 0.78, 28), (62, 1.0, 34), (88, 0.62, 24)]
        let front: [(x: CGFloat, h: CGFloat, half: CGFloat)] = wide
            ? [(10, 0.52, 28), (54, 0.6, 30), (96, 0.5, 30), (140, 0.5, 30)]
            : []

        for (isFront, peaks) in [(false, back), (true, front)] {
            for peak in peaks {
                let x = peak.x + rng.value(in: -3 ... 3)
                let h = peak.h * 92
                let base: CGFloat = 100
                let apex = CGPoint(x: x, y: base - h)
                let left = CGPoint(x: x - peak.half, y: base)
                let right = CGPoint(x: x + peak.half, y: base)
                let mid = CGPoint(x: x + peak.half * 0.1, y: base)

                var lit = Path()
                lit.move(to: apex); lit.addLine(to: left); lit.addLine(to: mid); lit.closeSubpath()
                var shaded = Path()
                shaded.move(to: apex); shaded.addLine(to: mid); shaded.addLine(to: right); shaded.closeSubpath()
                // The back row is a step paler, so the range has depth without a gradient.
                d.fill(lit, isFront ? p.dome : p.dome.opacity(0.78))
                d.fill(shaded, isFront ? p.domeShade : p.domeShade.opacity(0.85))

                // Snow: a cap with a jagged lower edge.
                let cap = h * 0.30
                var snow = Path()
                snow.move(to: apex)
                snow.addLine(to: CGPoint(x: x - peak.half * 0.30, y: base - h + cap))
                snow.addLine(to: CGPoint(x: x - peak.half * 0.13, y: base - h + cap * 0.62))
                snow.addLine(to: CGPoint(x: x + peak.half * 0.02, y: base - h + cap * 0.95))
                snow.addLine(to: CGPoint(x: x + peak.half * 0.16, y: base - h + cap * 0.55))
                snow.closeSubpath()
                d.fill(snow, p.snow)
            }
        }
    }
}

struct AlpineRange: View {
    var night = false
    var wide = true
    var seed = 1

    var body: some View {
        let drawing = AlpsDrawing(wide: wide, seed: seed)
        Canvas { context, size in
            var d = Draw(context, box: drawing.boxSize, size: size)
            drawing.draw(&d, .of(night: night))
        }
        .aspectRatio(drawing.boxSize.width / drawing.boxSize.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Arcades

/// A run of Turin's arcaded façades under red roofs, in buildings of different
/// heights: two floors of windows over a ground floor of round arches.
struct ArcadesDrawing: LandmarkDrawing {
    var seed = 1
    static let box = CGSize(width: 200, height: 60)

    func draw(_ d: inout Draw, _ p: SkylinePalette) {
        var rng = SkylineRandom(seed: seed)
        var x: CGFloat = 0
        while x < 200 {
            let width = min(rng.value(in: 34 ... 62), 200 - x)
            let floors = rng.int(in: 2 ... 3)
            let top: CGFloat = 60 - 14 - CGFloat(floors) * 11 - 8
            let roofHeight: CGFloat = 8
            let facade = x.truncatingRemainder(dividingBy: 3) > 1 ? p.facade : p.stone

            // Roof, façade, floors of windows, ground-floor arches.
            d.rect(x, top, width, 60 - top, facade)
            d.poly([(x, top + roofHeight), (x + 4, top), (x + width - 4, top), (x + width, top + roofHeight)], p.roof)
            if rng.int(in: 0 ... 2) == 0 {
                d.rect(x + width * 0.3, top - 5, 3, 6, p.roof)
            }
            for floor in 0 ..< floors {
                d.windowRow(x + 2, top + roofHeight + 3 + CGFloat(floor) * 11, width - 4, 6, count: max(3, Int(width / 9)), fraction: 0.42, p.ink)
            }
            d.archRow(x + 1, 60 - 14, width - 2, 14, count: max(3, Int(width / 9)), fraction: 0.58, p.ink)
            d.rect(x, 60 - 15.4, width, 1.2, p.ink.opacity(0.3))
            // A hairline between neighbouring buildings.
            d.rect(x, top, 0.9, 60 - top, p.ink.opacity(0.4))
            x += width
        }
    }
}

struct TurinArcades: View {
    var night = false
    var seed = 1
    var body: some View { DrawnLandmark(ArcadesDrawing(seed: seed), palette: .of(night: night)) }
}

// MARK: - The bull

/// The bull in profile: a heavy nape, a brow sloping to a square muzzle, an ear and
/// a horn rising from the poll. It is the same animal as the spout on the toret,
/// which is a bull's head in profile too.
struct BullProfileDrawing: LandmarkDrawing {
    static let box = CGSize(width: 90, height: 84)

    func draw(_ d: inout Draw, _ p: SkylinePalette) {
        // Head and neck, in one piece.
        var head = Path()
        head.move(to: CGPoint(x: 0, y: 84))
        head.addLine(to: CGPoint(x: 0, y: 58))
        head.addCurve(to: CGPoint(x: 26, y: 30), control1: CGPoint(x: 2, y: 42), control2: CGPoint(x: 12, y: 30))
        head.addCurve(to: CGPoint(x: 46, y: 27), control1: CGPoint(x: 34, y: 30), control2: CGPoint(x: 40, y: 28))
        head.addCurve(to: CGPoint(x: 74, y: 46), control1: CGPoint(x: 58, y: 28), control2: CGPoint(x: 67, y: 37))
        head.addCurve(to: CGPoint(x: 86, y: 62), control1: CGPoint(x: 80, y: 52), control2: CGPoint(x: 86, y: 56))
        head.addCurve(to: CGPoint(x: 74, y: 70), control1: CGPoint(x: 86, y: 68), control2: CGPoint(x: 80, y: 72))
        head.addLine(to: CGPoint(x: 62, y: 66))
        head.addCurve(to: CGPoint(x: 42, y: 77), control1: CGPoint(x: 54, y: 68), control2: CGPoint(x: 47, y: 71))
        head.addLine(to: CGPoint(x: 38, y: 84))
        head.closeSubpath()
        d.fill(head, p.silhouette)

        // Ear, laid back from the poll.
        d.poly([(38, 33), (22, 23), (34, 41)], p.silhouette)

        // Horn: out of the poll, up and forward.
        var horn = Path()
        horn.move(to: CGPoint(x: 41, y: 31))
        horn.addCurve(to: CGPoint(x: 62, y: 5), control1: CGPoint(x: 36, y: 19), control2: CGPoint(x: 46, y: 6))
        horn.addCurve(to: CGPoint(x: 51, y: 29), control1: CGPoint(x: 52, y: 12), control2: CGPoint(x: 52, y: 22))
        horn.closeSubpath()
        d.fill(horn, p.stone)
        d.stroke(horn, p.silhouette, width: 1.2)

        // Eye and nostril, cut out of the head.
        d.ellipse(61, 42, 2.4, 2.4, p.cutout)
        d.ellipse(80, 60, 1.7, 1.7, p.cutout)
    }
}

/// The bull from the front: a wide brow, two horns curving up, a tapering muzzle.
struct BullFrontDrawing: LandmarkDrawing {
    static let box = CGSize(width: 80, height: 84)

    func draw(_ d: inout Draw, _ p: SkylinePalette) {
        func mirrored(_ path: Path) -> Path {
            path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 80, ty: 0))
        }
        // Horns.
        var horn = Path()
        horn.move(to: CGPoint(x: 25, y: 36))
        horn.addCurve(to: CGPoint(x: 4, y: 10), control1: CGPoint(x: 8, y: 36), control2: CGPoint(x: 2, y: 24))
        horn.addCurve(to: CGPoint(x: 27, y: 27), control1: CGPoint(x: 11, y: 22), control2: CGPoint(x: 19, y: 25))
        horn.closeSubpath()
        for path in [horn, mirrored(horn)] {
            d.fill(path, p.stone)
            d.stroke(path, p.silhouette, width: 1.2)
        }
        // Ears.
        d.ellipse(15, 41, 9, 3.6, p.silhouette)
        d.ellipse(65, 41, 9, 3.6, p.silhouette)
        // Head: brow, cheeks, muzzle.
        var head = Path()
        head.move(to: CGPoint(x: 24, y: 27))
        head.addLine(to: CGPoint(x: 56, y: 27))
        head.addCurve(to: CGPoint(x: 60, y: 52), control1: CGPoint(x: 60, y: 32), control2: CGPoint(x: 62, y: 44))
        head.addCurve(to: CGPoint(x: 53, y: 78), control1: CGPoint(x: 58, y: 62), control2: CGPoint(x: 58, y: 72))
        head.addCurve(to: CGPoint(x: 27, y: 78), control1: CGPoint(x: 47, y: 83), control2: CGPoint(x: 33, y: 83))
        head.addCurve(to: CGPoint(x: 20, y: 52), control1: CGPoint(x: 22, y: 72), control2: CGPoint(x: 22, y: 62))
        head.addCurve(to: CGPoint(x: 24, y: 27), control1: CGPoint(x: 18, y: 44), control2: CGPoint(x: 20, y: 32))
        head.closeSubpath()
        d.fill(head, p.silhouette)
        // Eyes and nostrils, cut out of the head.
        d.ellipse(29.5, 42, 2.8, 2.2, p.cutout)
        d.ellipse(50.5, 42, 2.8, 2.2, p.cutout)
        d.ellipse(35, 71, 2.1, 2.8, p.cutout)
        d.ellipse(45, 71, 2.1, 2.8, p.cutout)
    }
}

struct TurinBull: View {
    enum Pose { case profile, front }
    var pose: Pose = .profile
    var night = false

    var body: some View {
        switch pose {
        case .profile: DrawnLandmark(BullProfileDrawing(), palette: .of(night: night))
        case .front: DrawnLandmark(BullFrontDrawing(), palette: .of(night: night))
        }
    }
}
