import SwiftUI

// The vocabulary of the poster: a handful of flat shapes, used as information.
//
// A circle is water that runs, a half-disc is a thin flow, a triangle is a dry
// bowl, an empty ring is "nobody has said". The sun, the river stripes, the
// chequered diamond and the Alps are the same shapes grown large, and they are
// the only decoration the app has.

// MARK: - Basic shapes

/// A triangle standing on its base.
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The upper half of a circle, flat side down.
struct HalfDisc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width / 2, rect.height)
        path.move(to: CGPoint(x: rect.midX - radius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY), radius: radius,
            startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

/// A square stood on its corner.
struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Water state

/// The state of the water, drawn as a shape so colour is never the only channel.
///
/// Blue circle: running. Yellow half-disc: weak. Red triangle: dry. Empty ring:
/// nobody has reported. At small sizes each carries a black outline, because
/// yellow on cream does not reach 3:1 on its own.
struct StateMark: View {
    let state: WaterState
    var size: CGFloat = 16
    var night = false
    /// Drop the outline for the large, poster-scale uses.
    var outlined = true

    private var ink: Color { night ? Palette.carta : Palette.inchiostro }

    var body: some View {
        Group {
            switch state {
            case .running:
                Circle().fill(state.color(night: night))
                    .overlay { if outlined { Circle().strokeBorder(ink, lineWidth: stroke) } }
            case .weak:
                ZStack {
                    Circle().strokeBorder(ink, lineWidth: stroke)
                    HalfDisc().fill(state.color(night: night))
                        .frame(width: size - stroke * 2, height: (size - stroke * 2) / 2)
                        .offset(y: -(size - stroke * 2) / 4)
                        .overlay {
                            if outlined {
                                Rectangle().fill(ink).frame(height: stroke)
                                    .offset(y: 0)
                            }
                        }
                }
            case .dry:
                Triangle().fill(state.color(night: night))
                    .overlay { if outlined { Triangle().stroke(ink, lineWidth: stroke) } }
            case .unknown:
                Circle().strokeBorder(state.color(night: night), lineWidth: max(1.5, stroke))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var stroke: CGFloat { max(1.25, size * 0.1) }
}

// MARK: - Structure

/// A rule of the weight the poster uses: heavy for structure, light between rows.
struct PosterRule: View {
    enum Weight { case heavy, light }
    var weight: Weight = .heavy
    var color: Color = Palette.inchiostro

    var body: some View {
        Rectangle()
            .fill(weight == .heavy ? color : color.opacity(0.35))
            .frame(height: weight == .heavy ? 3 : 1.5)
            .accessibilityHidden(true)
    }
}

/// A screen title: huge, black, broken over two lines, with the poster's vertical
/// rule down its left edge.
///
/// The break is the point. "TU / RIN" is two syllables stacked until they fill the
/// width of the plate, and the app's own titles — "PER / TO", "SAL / VAS" — are
/// cut the same way, so the type itself is the graphic.
struct PosterTitle: View {
    let lines: [String]
    var size: CGFloat = 84
    var color: Color = Palette.inchiostro
    var ruleColor: Color = Palette.inchiostro

    init(_ lines: String..., size: CGFloat = 84, color: Color = Palette.inchiostro, ruleColor: Color = Palette.inchiostro) {
        self.lines = lines
        self.size = size
        self.color = color
        self.ruleColor = ruleColor
    }

    var body: some View {
        let font = Typo.uiDisplay(size, 900)
        HStack(alignment: .top, spacing: size * 0.16) {
            Rectangle().fill(ruleColor).frame(width: 3)
            VStack(alignment: .leading, spacing: font.pointSize * 0.8 - font.lineHeight) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.uppercased())
                        .font(Font(font))
                        .tracking(Typo.tracking(-0.01, at: size))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(lines.joined(separator: " "))
        .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// A plate printed on the stock: flat fill, a black frame, square corners.
    ///
    /// Replaces the glass of the first version. Nothing here blurs what is behind
    /// it; a plate is an opaque piece of paper laid on top.
    func plate(
        fill: Color = Palette.carta, border: Color = Palette.inchiostro, lineWidth: CGFloat = 2.5
    ) -> some View {
        background(fill)
            .overlay { Rectangle().strokeBorder(border, lineWidth: lineWidth) }
    }
}

// MARK: - The sun and the river

/// The poster's yellow sun. Always behind the thing it is about.
struct SunDisc: View {
    var color: Color = Palette.sole

    var body: some View {
        Circle().fill(color).accessibilityHidden(true)
    }
}

/// The river: horizontal blue bands separated by hairlines of stock.
///
/// Drawn in a canvas so it can be any size without the bands blurring, and so
/// the bands can be set to drift sideways when the water is running.
struct WaterStripes: View {
    var bands = 4
    var color: Color = Palette.blu
    var gap: Color = Palette.carta
    /// Drifts the gaps sideways, one slow loop, when the water is running.
    var flowing = false

    var body: some View {
        TimelineView(.animation(minimumInterval: flowing ? 1 / 30 : nil, paused: !flowing)) { timeline in
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color))
                let bandHeight = size.height / CGFloat(bands)
                let line: CGFloat = max(1.5, bandHeight * 0.1)
                let seconds = timeline.date.timeIntervalSinceReferenceDate
                for index in 1 ..< bands {
                    let y = bandHeight * CGFloat(index) - line / 2
                    guard flowing else {
                        context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: line)), with: .color(gap))
                        continue
                    }
                    // Each gap is a dashed line, and alternate lines run in
                    // opposite directions: a river with a current in it.
                    let dash = size.width * 0.18
                    let period = dash * 2
                    let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
                    let shift = CGFloat((seconds * 18).truncatingRemainder(dividingBy: Double(period))) * direction
                    var x = -period + shift
                    while x < size.width {
                        context.fill(
                            Path(CGRect(x: x, y: y, width: dash, height: line)), with: .color(gap)
                        )
                        x += period
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The chequered diamond

/// The poster's lozenge of red, stock and sage squares: the diamond Turin puts on
/// its flags and its floors. Three by three cells on a corner.
struct DiamondChecker: View {
    var primary: Color = Palette.rosso
    var secondary: Color = Palette.salvia
    var stock: Color = Palette.cartaChiara
    var edge: Color = Palette.inchiostro

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width / sqrt(2)
            let cell = side / 3
            VStack(spacing: 0) {
                ForEach(0 ..< 3, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0 ..< 3, id: \.self) { column in
                            Rectangle().fill(color(row: row, column: column))
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .overlay { Rectangle().strokeBorder(edge, lineWidth: 2) }
            .rotationEffect(.degrees(45))
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func color(row: Int, column: Int) -> Color {
        if row == 1, column == 1 { return secondary }
        return (row + column).isMultiple(of: 2) ? stock : primary
    }
}

// MARK: - The Alps

/// Three or four triangular peaks in the poster's greys and greens, with a lit
/// facet on each so they read as faceted rock rather than as cut paper.
struct MountainRange: View {
    var body: some View {
        Canvas { context, size in
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * size.width, y: y * size.height)
            }
            func polygon(_ points: [CGPoint], _ color: Color) {
                var path = Path()
                path.move(to: points[0])
                for next in points.dropFirst() { path.addLine(to: next) }
                path.closeSubpath()
                context.fill(path, with: .color(color))
            }
            // Back peak, then the two in front; each has a shaded and a lit side.
            polygon([point(0.34, 0.0), point(0.7, 1), point(0.0, 1)], Palette.salvia)
            polygon([point(0.34, 0.0), point(0.7, 1), point(0.38, 1)], Palette.salviaScura)
            polygon([point(0.34, 0.0), point(0.44, 0.22), point(0.26, 0.2)], Palette.cartaChiara)
            polygon([point(0.74, 0.12), point(1.0, 1), point(0.46, 1)], Palette.salvia)
            polygon([point(0.74, 0.12), point(1.0, 1), point(0.78, 1)], Palette.salviaScura)
            polygon([point(0.74, 0.12), point(0.82, 0.3), point(0.67, 0.3)], Palette.cartaChiara)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The arcades

/// A run of porticoes under a red roof line: ochre façade, round arches in ink.
struct ArcadeStrip: View {
    var bays = 8
    var facade: Color = Palette.facciata
    var roof: Color = Palette.rosso
    var arch: Color = Palette.inchiostro

    var body: some View {
        Canvas { context, size in
            let roofHeight = size.height * 0.2
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: roofHeight)), with: .color(roof))
            context.fill(
                Path(CGRect(x: 0, y: roofHeight, width: size.width, height: size.height - roofHeight)),
                with: .color(facade)
            )
            let bay = size.width / CGFloat(bays)
            let archWidth = bay * 0.52
            let archTop = roofHeight + (size.height - roofHeight) * 0.28
            for index in 0 ..< bays {
                let x = bay * CGFloat(index) + (bay - archWidth) / 2
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x, y: archTop + archWidth / 2))
                path.addArc(
                    center: CGPoint(x: x + archWidth / 2, y: archTop + archWidth / 2),
                    radius: archWidth / 2, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false
                )
                path.addLine(to: CGPoint(x: x + archWidth, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(arch))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The Mole

/// The Mole Antonelliana, in the poster's own construction: a colonnaded base, a
/// ribbed green dome, a lantern in stepped tiers, and the needle of the spire.
///
/// It is the app's one portrait. Every other thing is a plain shape; this is the
/// building you can raise your eyes to and find from anywhere in the city, which
/// is the same job the compass does.
struct MoleSilhouette: View {
    var dome: Color = Palette.salvia
    var domeShade: Color = Palette.salviaScura
    var stone: Color = Palette.cartaChiara
    var ink: Color = Palette.inchiostro

    /// Width : height of the whole figure.
    static let aspect: CGFloat = 0.5

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> Path {
                Path(CGRect(x: x * w, y: y * h, width: width * w, height: height * h))
            }

            // Spire: a long needle with a star on the tip.
            var spire = Path()
            spire.move(to: CGPoint(x: 0.5 * w, y: 0))
            spire.addLine(to: CGPoint(x: 0.53 * w, y: 0.26 * h))
            spire.addLine(to: CGPoint(x: 0.47 * w, y: 0.26 * h))
            spire.closeSubpath()
            context.fill(spire, with: .color(ink))
            context.fill(Path(ellipseIn: CGRect(x: 0.485 * w, y: -0.004 * h, width: 0.03 * w, height: 0.02 * h)), with: .color(ink))

            // Lantern tiers, narrowing upward, with a lit window band on each.
            let tiers: [(y: CGFloat, width: CGFloat, height: CGFloat)] = [
                (0.26, 0.12, 0.05), (0.31, 0.2, 0.05), (0.36, 0.28, 0.06),
            ]
            for tier in tiers {
                let x = 0.5 - tier.width / 2
                context.fill(rect(x, tier.y, tier.width, tier.height), with: .color(stone))
                context.stroke(rect(x, tier.y, tier.width, tier.height), with: .color(ink), lineWidth: 1.2)
                for column in 1 ..< 5 {
                    let cx = x + tier.width * CGFloat(column) / 5
                    context.fill(rect(cx - 0.004, tier.y + tier.height * 0.2, 0.008, tier.height * 0.6), with: .color(ink))
                }
            }

            // The dome: a pointed vault with its ribs.
            var vault = Path()
            vault.move(to: CGPoint(x: 0.14 * w, y: 0.62 * h))
            vault.addCurve(
                to: CGPoint(x: 0.5 * w, y: 0.42 * h),
                control1: CGPoint(x: 0.16 * w, y: 0.5 * h), control2: CGPoint(x: 0.4 * w, y: 0.43 * h)
            )
            vault.addCurve(
                to: CGPoint(x: 0.86 * w, y: 0.62 * h),
                control1: CGPoint(x: 0.6 * w, y: 0.43 * h), control2: CGPoint(x: 0.84 * w, y: 0.5 * h)
            )
            vault.closeSubpath()
            context.fill(vault, with: .color(dome))
            // Shade the right half, then draw the ribs over both.
            context.clipToLayer { layer in layer.fill(vault, with: .color(.black)) }
            context.fill(rect(0.5, 0.4, 0.4, 0.24), with: .color(domeShade))
            for index in 0 ..< 9 {
                let x = 0.2 + 0.075 * CGFloat(index)
                var rib = Path()
                rib.move(to: CGPoint(x: x * w, y: 0.62 * h))
                rib.addLine(to: CGPoint(x: (0.5 + (x - 0.5) * 0.12) * w, y: 0.43 * h))
                context.stroke(rib, with: .color(ink.opacity(0.55)), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }
}
