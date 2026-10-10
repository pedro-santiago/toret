import SwiftUI

// The drawing kit under every landmark.
//
// A landmark is drawn once, in a fixed box of design units, and scaled to fit:
// the same drawing is 40 pt wide on a compass rim and 300 pt wide on a launch
// screen. Everything is flat fills. There are no gradients, blurs or shadows, and
// the only "shading" is a second flat tone laid over the shaded half of a form,
// the way the poster does it.

/// The inks a landmark is printed in.
///
/// `ink` is the colour of everything cut out of the building (windows, arches,
/// the gaps between columns). By day it is black; on the night plate it is the
/// night itself, so the openings read as holes in the stone rather than as
/// light-on-dark ghosts.
struct SkylinePalette: Sendable {
    var ink: Color
    /// Forms that are drawn as dark shapes standing against the sky: spires, a
    /// statue. Black by day, and the lightest ink at night, so they never vanish.
    var silhouette: Color
    /// The colour of the ground the drawing stands on, for a hole cut through a
    /// dark silhouette (an eye, a nostril).
    var cutout: Color
    /// The low dark ground a building stands on.
    var slab: Color
    var stone: Color
    var facade: Color
    var roof: Color
    var dome: Color
    var domeShade: Color
    var snow: Color
    var brick: Color
    var water: Color
    /// Laid over the shaded half of a form, on top of whatever it was filled with.
    var shade: Color
    var sun: Color
    var dot: Color

    static let day = SkylinePalette(
        ink: Palette.inchiostro, silhouette: Palette.inchiostro, cutout: Palette.carta, slab: Palette.inchiostro,
        stone: Palette.cartaChiara, facade: Palette.facciata,
        roof: Palette.rosso, dome: Palette.salvia, domeShade: Palette.salviaScura,
        snow: Palette.cartaChiara, brick: Palette.rosso, water: Palette.blu,
        shade: Palette.inchiostro.opacity(0.24), sun: Palette.sole, dot: Palette.rosso
    )

    static let night = SkylinePalette(
        ink: Palette.notte, silhouette: Palette.carta, cutout: Palette.notte, slab: Palette.salviaScura,
        stone: Palette.carta, facade: Palette.cartaScura,
        roof: Palette.seccaNotte, dome: Palette.salvia, domeShade: Palette.salviaScura,
        snow: Palette.cartaChiara, brick: Palette.seccaNotte, water: Palette.correnteNotte,
        shade: Palette.notte.opacity(0.30), sun: Palette.luna, dot: Palette.seccaNotte
    )

    static func of(night: Bool) -> SkylinePalette { night ? .night : .day }

    /// One flat colour for every form and nothing cut out of it: a silhouette, for
    /// the horizon behind a title where detail would only be noise.
    static func mono(_ color: Color) -> SkylinePalette {
        SkylinePalette(
            ink: .clear, silhouette: color, cutout: .clear, slab: color, stone: color, facade: color, roof: color, dome: color,
            domeShade: color, snow: color, brick: color, water: color,
            shade: .clear, sun: color, dot: color
        )
    }
}

/// A flat-fill pen over a fixed design box.
struct Draw {
    var context: GraphicsContext
    /// Device points per design unit, for the strokes that must not go finer than a pixel.
    let scale: CGFloat

    /// Fits `box` into `size`, centred across and standing on the bottom edge, so
    /// every landmark in a row shares one ground line whatever its proportions.
    init(_ context: GraphicsContext, box: CGSize, size: CGSize) {
        var c = context
        let s = min(size.width / box.width, size.height / box.height)
        c.translateBy(x: (size.width - box.width * s) / 2, y: size.height - box.height * s)
        c.scaleBy(x: s, y: s)
        self.context = c
        self.scale = s
    }

    /// A stroke width in design units that never renders thinner than `device` points.
    func px(_ units: CGFloat, atLeast device: CGFloat = 0.8) -> CGFloat {
        max(units, device / max(scale, 0.0001))
    }

    // MARK: Fills

    func fill(_ path: Path, _ color: Color) {
        context.fill(path, with: .color(color))
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
        fill(Path(CGRect(x: x, y: y, width: w, height: h)), color)
    }

    func poly(_ points: [(CGFloat, CGFloat)], _ color: Color) {
        fill(Self.polygon(points), color)
    }

    func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ color: Color) {
        fill(Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)), color)
    }

    /// A rectangle with a round head: the arch every window and arcade is made of.
    func arch(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
        fill(Self.archPath(x, y, w, h), color)
    }

    /// The upper half of an ellipse standing on `baseY`.
    func dome(_ cx: CGFloat, _ baseY: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ color: Color) {
        fill(Self.domePath(cx, baseY, rx, ry), color)
    }

    /// The right half of `domePath`, for the shaded side.
    func domeRight(_ cx: CGFloat, _ baseY: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ color: Color) {
        var p = Path()
        p.move(to: CGPoint(x: cx, y: baseY))
        p.addLine(to: CGPoint(x: cx, y: baseY - ry))
        p.addCurve(
            to: CGPoint(x: cx + rx, y: baseY),
            control1: CGPoint(x: cx + rx * 0.55, y: baseY - ry),
            control2: CGPoint(x: cx + rx, y: baseY - ry * 0.55)
        )
        p.closeSubpath()
        fill(p, color)
    }

    func line(_ a: CGPoint, _ b: CGPoint, _ color: Color, width: CGFloat = 1) {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        context.stroke(p, with: .color(color), lineWidth: px(width))
    }

    func hline(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ color: Color, width: CGFloat = 1) {
        line(CGPoint(x: x, y: y), CGPoint(x: x + w, y: y), color, width: width)
    }

    func stroke(_ path: Path, _ color: Color, width: CGFloat = 1) {
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: px(width), lineJoin: .round))
    }

    // MARK: Rows

    /// `count` upright strips of `ink` across `[x, x + w]`, standing in for the gaps
    /// between the columns of a colonnade drawn on a stone ground.
    func colonnade(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, count: Int, gapFraction: CGFloat = 0.42, _ ink: Color) {
        guard count > 0 else { return }
        let pitch = w / CGFloat(count)
        let gap = pitch * gapFraction
        for i in 0 ..< count {
            rect(x + pitch * CGFloat(i) + (pitch - gap) / 2, y, gap, h, ink)
        }
    }

    /// A row of round-headed openings.
    func archRow(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, count: Int, fraction: CGFloat = 0.56, _ color: Color) {
        guard count > 0 else { return }
        let pitch = w / CGFloat(count)
        let aw = pitch * fraction
        for i in 0 ..< count {
            arch(x + pitch * CGFloat(i) + (pitch - aw) / 2, y, aw, h, color)
        }
    }

    /// A row of square windows.
    func windowRow(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, count: Int, fraction: CGFloat = 0.42, _ color: Color) {
        guard count > 0 else { return }
        let pitch = w / CGFloat(count)
        let ww = pitch * fraction
        for i in 0 ..< count {
            rect(x + pitch * CGFloat(i) + (pitch - ww) / 2, y, ww, h, color)
        }
    }

    /// A four-pointed star: the Mole's finial.
    func star(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: Color) {
        let inner = r * 0.28
        var points: [(CGFloat, CGFloat)] = []
        for i in 0 ..< 8 {
            let angle = CGFloat(i) * .pi / 4 - .pi / 2
            let radius = i.isMultiple(of: 2) ? r : inner
            points.append((cx + cos(angle) * radius, cy + sin(angle) * radius))
        }
        poly(points, color)
    }

    // MARK: Paths

    static func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: CGPoint(x: first.0, y: first.1))
        for next in points.dropFirst() { p.addLine(to: CGPoint(x: next.0, y: next.1)) }
        p.closeSubpath()
        return p
    }

    static func archPath(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
        let r = min(w / 2, h)
        var p = Path()
        p.move(to: CGPoint(x: x, y: y + h))
        p.addLine(to: CGPoint(x: x, y: y + r))
        p.addArc(
            center: CGPoint(x: x + w / 2, y: y + r), radius: w / 2,
            startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false
        )
        p.addLine(to: CGPoint(x: x + w, y: y + h))
        p.closeSubpath()
        return p
    }

    static func domePath(_ cx: CGFloat, _ baseY: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: cx - rx, y: baseY))
        p.addCurve(
            to: CGPoint(x: cx, y: baseY - ry),
            control1: CGPoint(x: cx - rx, y: baseY - ry * 0.55),
            control2: CGPoint(x: cx - rx * 0.55, y: baseY - ry)
        )
        p.addCurve(
            to: CGPoint(x: cx + rx, y: baseY),
            control1: CGPoint(x: cx + rx * 0.55, y: baseY - ry),
            control2: CGPoint(x: cx + rx, y: baseY - ry * 0.55)
        )
        p.closeSubpath()
        return p
    }
}

/// A building that knows its own proportions and how to draw itself.
protocol LandmarkDrawing: Sendable {
    /// The design box, in units. Width : height is the landmark's aspect.
    static var box: CGSize { get }
    func draw(_ d: inout Draw, _ p: SkylinePalette)
}

extension LandmarkDrawing {
    static var aspect: CGFloat { box.width / box.height }
}

/// Any `LandmarkDrawing`, as a view.
struct DrawnLandmark<D: LandmarkDrawing>: View {
    let drawing: D
    var palette: SkylinePalette

    init(_ drawing: D, palette: SkylinePalette = .day) {
        self.drawing = drawing
        self.palette = palette
    }

    var body: some View {
        Canvas { context, size in
            var d = Draw(context, box: D.box, size: size)
            drawing.draw(&d, palette)
        }
        .aspectRatio(D.aspect, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
