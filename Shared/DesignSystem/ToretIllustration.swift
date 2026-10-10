import SwiftUI

// The toret, drawn.
//
// Turin's public fountains are cast-iron columns with a bull's head for a spout,
// and nothing else in the city looks like them. The poster draws the Mole; this
// draws the thing the app is actually about, in the same flat inks, standing
// under the same sun in front of the same arcades.
//
// Everything is one `Canvas` in a fixed 84 × 100 box that is scaled to fit, so it
// is crisp at 60 px on the home screen and at 400 pt in the detail header, and it
// is the same drawing in both. The water is honest: it follows the community's
// word and never runs because the picture would look better with it.

// MARK: - Colours

/// The inks a figure is printed in. The poster uses the real ones; the icon and
/// the tinted variants swap in flatter sets.
struct FigurePalette: Sendable {
    var column: Color
    var facet: Color
    var ink: Color
    var horn: Color
    var water: Color
    var eye: Color
    var bowlInner: Color
    var gap: Color

    /// Cast iron, as it is on the street: grey-green, black head, pale horns.
    static let poster = FigurePalette(
        column: Palette.salviaScura, facet: Palette.salvia, ink: Palette.inchiostro,
        horn: Palette.cartaChiara, water: Palette.blu, eye: Palette.cartaChiara,
        bowlInner: Palette.cartaScura, gap: Palette.carta
    )

    /// One ink for the whole figure, for the icon and for small sizes.
    static let silhouette = FigurePalette(
        column: Palette.inchiostro, facet: Palette.inchiostro, ink: Palette.inchiostro,
        horn: Palette.inchiostro, water: Palette.blu, eye: Palette.carta,
        bowlInner: Palette.cartaScura, gap: Palette.carta
    )

    /// For a night plate: the figure goes light on the dark ground.
    static let night = FigurePalette(
        column: Palette.carta, facet: Palette.cartaChiara, ink: Palette.carta,
        horn: Palette.carta, water: Palette.correnteNotte, eye: Palette.notte,
        bowlInner: Palette.notteChiara, gap: Palette.notte
    )

    /// Greys only: the tinted icon is recoloured by the system.
    static func grey(ink: Double, mid: Double, water: Double, ground: Double) -> FigurePalette {
        FigurePalette(
            column: Color(white: ink), facet: Color(white: ink), ink: Color(white: ink),
            horn: Color(white: ink), water: Color(white: water), eye: Color(white: ground),
            bowlInner: Color(white: mid), gap: Color(white: ground)
        )
    }
}

// MARK: - The figure

/// One fountain, standing alone: the column, the spout, the bowl, the water.
///
/// `kind` picks the pattern, so a plain tap on a pillar never claims to be a bull.
/// `state` decides what the water is doing:
///
/// - running: a living blue arc, falling drops, a bowl with a current in it;
/// - weak: a thin thread and a shallow bowl;
/// - dry: no water, a red triangle on the rim;
/// - unknown: no water drawn at all and an empty ring, because nobody has said.
struct ToretFigure: View {
    let kind: FountainKind
    var state: WaterState = .unknown
    var palette: FigurePalette = .poster
    /// Lets the water move. The caller decides; the figure never loops on its own
    /// when it is off screen or Reduce Motion is on.
    var isLive = false

    /// Width : height of the figure's box.
    static let aspect: CGFloat = Local.width / Local.height

    var body: some View {
        Group {
            if isLive && (state == .running || state == .weak) {
                TimelineView(.animation) { timeline in
                    canvas(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                canvas(time: nil)
            }
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func canvas(time: Double?) -> some View {
        Canvas { context, size in
            let scale = min(size.width / Local.width, size.height / Local.height)
            context.translateBy(x: (size.width - Local.width * scale) / 2, y: size.height - Local.height * scale)
            context.scaleBy(x: scale, y: scale)
            FigureDrawing(kind: kind, state: state, palette: palette, time: time).draw(in: &context)
        }
    }
}

/// The fixed box every figure is drawn in.
private enum Local {
    static let width: CGFloat = 84
    static let height: CGFloat = 100
}

/// A flat-topped bowl: straight rim, curved belly.
private struct Bowl {
    static func path(_ rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.85),
            control2: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control1: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.85)
        )
        path.closeSubpath()
        return path
    }
}

private struct FigureDrawing {
    let kind: FountainKind
    let state: WaterState
    let palette: FigurePalette
    /// Seconds, or nil for a still frame.
    let time: Double?

    private var hasWater: Bool { state == .running || state == .weak }

    func draw(in context: inout GraphicsContext) {
        switch kind {
        case .toret: drawToret(&context)
        case .fountain: drawPillar(&context)
        case .bubbler: drawBubbler(&context)
        case .refill: drawRefill(&context)
        }
    }

    // MARK: Kinds

    /// The column with the bull's head.
    private func drawToret(_ context: inout GraphicsContext) {
        let p = palette
        // Plinth and flare.
        context.fill(Path(CGRect(x: 14, y: 90, width: 32, height: 10)), with: .color(p.ink))
        context.fill(polygon([(21, 80), (39, 80), (43, 90), (17, 90)]), with: .color(p.column))
        // Shaft, with the lit side.
        context.fill(Path(CGRect(x: 21, y: 34, width: 18, height: 46)), with: .color(p.column))
        context.fill(Path(CGRect(x: 21, y: 34, width: 5, height: 46)), with: .color(p.facet))
        // Collars.
        for (y, h) in [(30.0, 4.0), (56.0, 3.0), (74.0, 3.0)] {
            context.fill(Path(CGRect(x: 19, y: y, width: 22, height: h)), with: .color(p.ink))
        }
        // Cap and knob.
        var cap = Path()
        cap.move(to: CGPoint(x: 21, y: 30))
        cap.addCurve(to: CGPoint(x: 30, y: 19), control1: CGPoint(x: 21, y: 23), control2: CGPoint(x: 25, y: 19))
        cap.addCurve(to: CGPoint(x: 39, y: 30), control1: CGPoint(x: 35, y: 19), control2: CGPoint(x: 39, y: 23))
        cap.closeSubpath()
        context.fill(cap, with: .color(p.ink))
        context.fill(Path(ellipseIn: CGRect(x: 27.8, y: 15.3, width: 4.4, height: 4.4)), with: .color(p.ink))

        // Horn, then head, so the head overlaps the horn's root.
        var horn = Path()
        horn.move(to: CGPoint(x: 44, y: 38.5))
        horn.addCurve(to: CGPoint(x: 56, y: 26.5), control1: CGPoint(x: 43, y: 31), control2: CGPoint(x: 49, y: 26.5))
        horn.addCurve(to: CGPoint(x: 48.5, y: 38.5), control1: CGPoint(x: 51.5, y: 29.5), control2: CGPoint(x: 49, y: 33.5))
        horn.closeSubpath()
        context.fill(horn, with: .color(p.horn))
        context.stroke(horn, with: .color(p.ink), lineWidth: p.horn == p.ink ? 0 : 0.9)

        var head = Path()
        head.move(to: CGPoint(x: 39, y: 40))
        head.addCurve(to: CGPoint(x: 49, y: 37), control1: CGPoint(x: 42, y: 37.5), control2: CGPoint(x: 46, y: 36.5))
        head.addCurve(to: CGPoint(x: 60, y: 46), control1: CGPoint(x: 55, y: 37.5), control2: CGPoint(x: 60, y: 41))
        head.addLine(to: CGPoint(x: 60.6, y: 51))
        head.addCurve(to: CGPoint(x: 55, y: 54.5), control1: CGPoint(x: 60.6, y: 53.5), control2: CGPoint(x: 58, y: 54.8))
        head.addLine(to: CGPoint(x: 39, y: 55))
        head.closeSubpath()
        context.fill(head, with: .color(p.ink))
        context.fill(Path(ellipseIn: CGRect(x: 49.2, y: 41.7, width: 2.6, height: 2.6)), with: .color(p.eye))
        context.fill(Path(ellipseIn: CGRect(x: 57.4, y: 46.7, width: 1.8, height: 1.8)), with: .color(p.eye))

        let bowl = CGRect(x: 49, y: 90, width: 28, height: 9)
        drawBowl(&context, bowl)
        drawStream(
            &context, from: CGPoint(x: 59.8, y: 54.2), control: CGPoint(x: 64, y: 60),
            to: CGPoint(x: 63, y: 90.5), width: 2.4
        )
        drawMarker(&context, at: CGPoint(x: 63, y: 83))
    }

    /// A plain pillar with a tap: not a bull, and not pretending to be.
    private func drawPillar(_ context: inout GraphicsContext) {
        let p = palette
        context.fill(Path(CGRect(x: 16, y: 90, width: 28, height: 10)), with: .color(p.ink))
        context.fill(Path(CGRect(x: 22, y: 32, width: 16, height: 58)), with: .color(p.column))
        context.fill(Path(CGRect(x: 22, y: 32, width: 4.5, height: 58)), with: .color(p.facet))
        context.fill(Path(CGRect(x: 18.5, y: 27, width: 23, height: 5)), with: .color(p.ink))
        // The tap: a short tube that bends down.
        var tube = Path()
        tube.move(to: CGPoint(x: 38, y: 43))
        tube.addLine(to: CGPoint(x: 46, y: 43))
        tube.addQuadCurve(to: CGPoint(x: 49.5, y: 48), control: CGPoint(x: 49.5, y: 43))
        context.stroke(tube, with: .color(p.ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        drawBowl(&context, CGRect(x: 49, y: 90, width: 28, height: 9))
        drawStream(
            &context, from: CGPoint(x: 49.5, y: 49.5), control: CGPoint(x: 62, y: 54),
            to: CGPoint(x: 63, y: 90.5), width: 2.2
        )
        drawMarker(&context, at: CGPoint(x: 63, y: 80))
    }

    /// A low post with a jet that rises and falls into its own dish.
    private func drawBubbler(_ context: inout GraphicsContext) {
        let p = palette
        context.fill(Path(CGRect(x: 18, y: 92, width: 30, height: 8)), with: .color(p.ink))
        context.fill(Path(CGRect(x: 26, y: 62, width: 14, height: 30)), with: .color(p.column))
        context.fill(Path(CGRect(x: 26, y: 62, width: 4, height: 30)), with: .color(p.facet))
        let dish = CGRect(x: 18, y: 54, width: 32, height: 9)
        context.fill(Bowl.path(dish), with: .color(p.ink))
        context.fill(Bowl.path(dish.insetBy(dx: 2, dy: 1.6).offsetBy(dx: 0, dy: -0.4)), with: .color(hasWater ? p.water : p.bowlInner))
        context.fill(Path(CGRect(x: 32, y: 49, width: 4, height: 6)), with: .color(p.ink))
        let lift: CGFloat = state == .running ? 17 : 8
        var jet = Path()
        jet.move(to: CGPoint(x: 34, y: 49))
        jet.addQuadCurve(to: CGPoint(x: 43, y: 56), control: CGPoint(x: 40, y: 49 - lift * 1.7))
        if state == .running {
            context.stroke(jet, with: .color(p.water), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            drawFlow(&context, along: jet, width: 2, dashPhaseSpeed: 16)
        } else if state == .weak {
            context.stroke(jet, with: .color(p.water), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
        drawMarker(&context, at: CGPoint(x: 62, y: 62))
    }

    /// A slim post with a bottle-filler panel, and a bottle under it.
    private func drawRefill(_ context: inout GraphicsContext) {
        let p = palette
        context.fill(Path(CGRect(x: 20, y: 90, width: 24, height: 10)), with: .color(p.ink))
        context.fill(Path(CGRect(x: 26, y: 22, width: 10, height: 68)), with: .color(p.column))
        context.fill(Path(CGRect(x: 26, y: 22, width: 3, height: 68)), with: .color(p.facet))
        context.fill(Path(CGRect(x: 36, y: 36, width: 15, height: 24)), with: .color(p.ink))
        context.fill(Path(ellipseIn: CGRect(x: 40.2, y: 41, width: 6.6, height: 6.6)), with: .color(p.eye))
        context.fill(Path(CGRect(x: 41, y: 60, width: 5, height: 5)), with: .color(p.ink))
        // The bottle under the spigot.
        let body = Path(roundedRect: CGRect(x: 39, y: 78, width: 10, height: 13), cornerRadius: 2)
        let neck = Path(CGRect(x: 42, y: 73, width: 4, height: 5.5))
        context.fill(body, with: .color(Palette.cartaChiara))
        context.fill(neck, with: .color(Palette.cartaChiara))
        if state == .running {
            context.fill(Path(CGRect(x: 39.6, y: 83, width: 8.8, height: 7.4)), with: .color(p.water))
        }
        context.stroke(body, with: .color(p.ink), lineWidth: 1.2)
        context.stroke(neck, with: .color(p.ink), lineWidth: 1.2)
        var stream = Path()
        stream.move(to: CGPoint(x: 44, y: 65))
        stream.addLine(to: CGPoint(x: 44, y: 76))
        if state == .running {
            context.stroke(stream, with: .color(p.water), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            drawFlow(&context, along: stream, width: 2, dashPhaseSpeed: 18)
        } else if state == .weak {
            context.stroke(stream, with: .color(p.water), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
        }
        context.fill(Path(CGRect(x: 52, y: 95, width: 22, height: 3.5)), with: .color(p.ink))
        drawMarker(&context, at: CGPoint(x: 63, y: 80))
    }

    // MARK: Water

    /// The bowl at the foot, and what is in it.
    private func drawBowl(_ context: inout GraphicsContext, _ rect: CGRect) {
        let p = palette
        context.fill(Bowl.path(rect), with: .color(p.ink))
        let inner = rect.insetBy(dx: 2.2, dy: 1.8).offsetBy(dx: 0, dy: -0.4)
        context.fill(Bowl.path(inner), with: .color(p.bowlInner))
        guard hasWater else { return }
        // The river, in miniature: blue with cream lines, drifting when live.
        context.drawLayer { layer in
            layer.clip(to: Bowl.path(inner))
            let level = state == .running ? inner.minY : inner.minY + inner.height * 0.45
            layer.fill(Path(CGRect(x: inner.minX, y: level, width: inner.width, height: inner.maxY - level)), with: .color(p.water))
            guard state == .running else { return }
            let lineHeight: CGFloat = 0.9
            for (index, y) in [inner.minY + inner.height * 0.34, inner.minY + inner.height * 0.68].enumerated() {
                let dash: CGFloat = inner.width * 0.22
                let period = dash * 2
                let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
                let shift = CGFloat((time ?? 0.4) * 5).truncatingRemainder(dividingBy: period) * direction
                var x = inner.minX - period + shift
                while x < inner.maxX {
                    layer.fill(Path(CGRect(x: x, y: y, width: dash, height: lineHeight)), with: .color(p.gap))
                    x += period
                }
            }
        }
    }

    /// The stream from the spout, with drops falling along it and a ring where it lands.
    private func drawStream(
        _ context: inout GraphicsContext, from start: CGPoint, control: CGPoint,
        to end: CGPoint, width: CGFloat
    ) {
        guard hasWater else { return }
        let p = palette
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)

        if state == .weak {
            // A thread: thin, straight down, and a single drop leaving the chin.
            var thread = Path()
            thread.move(to: start)
            thread.addLine(to: CGPoint(x: start.x + 0.8, y: start.y + (end.y - start.y) * 0.55))
            context.stroke(thread, with: .color(p.water), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
            let t = ((time ?? 0.3) * 0.8).truncatingRemainder(dividingBy: 1)
            let drop = CGPoint(x: start.x + 0.8, y: start.y + (end.y - start.y) * (0.55 + 0.45 * t))
            context.fill(Path(ellipseIn: CGRect(x: drop.x - 1, y: drop.y - 1, width: 2, height: 2)), with: .color(p.water))
            return
        }

        context.stroke(path, with: .color(p.water), style: StrokeStyle(lineWidth: width, lineCap: .round))
        drawFlow(&context, along: path, width: width, dashPhaseSpeed: 22)

        // Drops: three, spaced a third of the fall apart, each slightly to the side.
        let seconds = time ?? 0.35
        for index in 0 ..< 3 {
            let t = (seconds * 0.9 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
            let point = quadPoint(start, control, end, CGFloat(t))
            let side: CGFloat = index == 1 ? 2.2 : index == 2 ? -1.6 : 1
            context.fill(
                Path(ellipseIn: CGRect(x: point.x + side - 0.9, y: point.y - 0.9, width: 1.8, height: 1.8)),
                with: .color(p.water)
            )
        }
        // The ring where it lands.
        let ring = ((seconds * 0.9).truncatingRemainder(dividingBy: 1))
        let radius = 2 + 5 * CGFloat(ring)
        let landing = Path(ellipseIn: CGRect(x: end.x - radius, y: end.y - radius * 0.35, width: radius * 2, height: radius * 0.7))
        context.stroke(landing, with: .color(p.gap.opacity(1 - ring)), lineWidth: 0.9)
    }

    /// Cream dashes sliding along a stream: the sense of current without a gradient.
    private func drawFlow(_ context: inout GraphicsContext, along path: Path, width: CGFloat, dashPhaseSpeed: Double) {
        guard let time else { return }
        context.stroke(
            path, with: .color(palette.gap.opacity(0.85)),
            style: StrokeStyle(
                lineWidth: max(0.5, width * 0.22), lineCap: .butt,
                dash: [3.2, 7], dashPhase: -CGFloat(time * dashPhaseSpeed)
            )
        )
    }

    /// The red triangle or the empty ring that says what the water is not doing.
    private func drawMarker(_ context: inout GraphicsContext, at centre: CGPoint) {
        switch state {
        case .dry:
            let r: CGFloat = 4.6
            let triangle = polygon([(centre.x, centre.y - r), (centre.x + r, centre.y + r * 0.8), (centre.x - r, centre.y + r * 0.8)])
            context.fill(triangle, with: .color(Palette.rosso))
            context.stroke(triangle, with: .color(palette.ink), lineWidth: 1)
        case .unknown:
            context.stroke(
                Path(ellipseIn: CGRect(x: centre.x - 3.6, y: centre.y - 3.6, width: 7.2, height: 7.2)),
                with: .color(palette.ink.opacity(0.6)), lineWidth: 1.5
            )
        case .running, .weak:
            break
        }
    }

    // MARK: Geometry

    private func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.0, y: first.1))
        for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
        path.closeSubpath()
        return path
    }

    private func quadPoint(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * a.x + 2 * u * t * c.x + t * t * b.x,
            y: u * u * a.y + 2 * u * t * c.y + t * t * b.y
        )
    }
}

// MARK: - The setts

/// Turin's porphyry setts, laid in overlapping arcs: rows of scallops, each row
/// half a stone along from the last.
struct SettPavement: View {
    var ground: Color = Palette.facciata
    var line: Color = Palette.inchiostro.opacity(0.4)
    var stone: CGFloat = 13

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ground))
            let radius = stone / 2
            var row = 0
            var y: CGFloat = -radius * 0.2
            while y < size.height + radius {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : radius
                while x < size.width + stone {
                    var arc = Path()
                    arc.addArc(center: CGPoint(x: x, y: y), radius: radius, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                    context.stroke(arc, with: .color(line), lineWidth: 1.4)
                    x += stone
                }
                y += radius * 0.95
                row += 1
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The plate

/// The detail header: a toret under the sun, in front of the arcades, with the
/// Alps behind them. One composition, laid out from the foot of the plate up so
/// it keeps its ground when the plate is stretched.
struct ToretIllustration: View {
    let kind: FountainKind
    let state: WaterState
    /// Lets the water move. Off for thumbnails and for the compact empty states.
    var animated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var onScreen = true

    private var isLive: Bool {
        animated && onScreen && !reduceMotion && scenePhase == .active
    }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            // Everything sits on the horizon, a fixed distance above the foot, so
            // stretching the plate grows the sky and leaves the street alone.
            let street = min(h * 0.26, 96)
            let horizon = h - street
            let arcadeHeight = min(h * 0.17, 58)
            let figureHeight = min(h * 0.62, w * 0.9)
            let figureWidth = figureHeight * ToretFigure.aspect
            let figureLeft = w * 0.12

            ZStack(alignment: .topLeading) {
                Palette.carta

                SunDisc()
                    .frame(width: h * 0.58, height: h * 0.58)
                    .position(x: w * 0.60, y: h * 0.36)

                Circle().fill(Palette.rosso)
                    .frame(width: h * 0.075, height: h * 0.075)
                    .position(x: w * 0.9, y: h * 0.19)

                MountainRange()
                    .frame(width: w * 0.66, height: h * 0.3)
                    .position(x: w * 0.33, y: horizon - arcadeHeight - h * 0.15 + 6)

                ArcadeStrip(bays: max(6, Int(w / (arcadeHeight * 0.95))))
                    .frame(width: w, height: arcadeHeight)
                    .position(x: w / 2, y: horizon - arcadeHeight / 2)

                SettPavement(stone: max(11, h * 0.04))
                    .frame(width: w, height: street)
                    .position(x: w / 2, y: horizon + street / 2)

                Rectangle().fill(Palette.inchiostro)
                    .frame(width: w, height: 3)
                    .position(x: w / 2, y: horizon)

                ToretFigure(kind: kind, state: state, isLive: isLive)
                    .frame(width: figureWidth, height: figureHeight)
                    .position(x: figureLeft + figureWidth / 2, y: horizon + street * 0.58 - figureHeight / 2)
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .onAppear { onScreen = true }
        // A header scrolled out of sight should not keep redrawing the water.
        .onScrollVisibilityChange(threshold: 0.05) { onScreen = $0 }
        .accessibilityHidden(true)
    }
}

// MARK: - Empty states

/// A small composition for the moments a list has nothing to show: the toret
/// under the sun, with one mark that says why.
struct ToretEmptyArt: View {
    enum Reason {
        /// Nothing saved yet: an empty diamond waiting to be filled.
        case saved
        /// A search that found nothing: an empty ring.
        case noResults
        /// No connection: the river drawn flat, with a red triangle.
        case offline
    }

    let reason: Reason
    var kind: FountainKind = .toret

    var body: some View {
        ZStack {
            SunDisc().frame(width: 124, height: 124).offset(x: 18, y: -8)
            ToretFigure(kind: kind, state: .unknown)
                .frame(width: 104 * ToretFigure.aspect, height: 104)
                .offset(x: -26, y: 8)
            mark.offset(x: 46, y: -42)
        }
        .frame(width: 190, height: 140)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var mark: some View {
        switch reason {
        case .saved:
            Diamond().stroke(Palette.inchiostro, lineWidth: 3).frame(width: 34, height: 34)
        case .noResults:
            Circle().strokeBorder(Palette.inchiostro, lineWidth: 3).frame(width: 30, height: 30)
        case .offline:
            Triangle().fill(Palette.rosso).frame(width: 30, height: 28)
        }
    }
}

extension ToretIllustration {
    /// The compact empty-state art, ready to drop into a list.
    static func emptyState(_ reason: ToretEmptyArt.Reason, kind: FountainKind = .toret) -> some View {
        ToretEmptyArt(reason: reason, kind: kind)
    }
}

#Preview("Toret, running") {
    ToretIllustration(kind: .toret, state: .running).frame(height: 360)
}

#Preview("Kinds") {
    VStack(spacing: 0) {
        ForEach([FountainKind.fountain, .bubbler, .refill], id: \.self) { kind in
            ToretIllustration(kind: kind, state: .running).frame(height: 200)
        }
    }
}
