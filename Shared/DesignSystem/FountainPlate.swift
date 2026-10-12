import SwiftUI

/// One fountain's print: its own plate of the poster, drawn flat at any size.
///
/// A sun, a red dot, something from Turin standing behind, a ground with a few
/// stripes on it, and the fountain itself, a printed plate chosen by its kind.
/// All of it follows from `FountainPlateSpec`, so the same fountain is always the
/// same picture.
///
/// It is decoration and says so to VoiceOver. It also never shows water: no stream
/// from the spout, no puddle, no dry crack. What the water is doing is the state
/// shape's job, and a picture that disagreed with it would be worse than none.
struct FountainPlate: View {
    let spec: FountainPlateSpec
    var night = false
    /// Height at the top that the sun and the dot keep clear of, for a plate that
    /// bleeds under the status bar and the buttons pinned over it.
    var topInset: CGFloat = 0

    init(spec: FountainPlateSpec, night: Bool = false, topInset: CGFloat = 0) {
        self.spec = spec
        self.night = night
        self.topInset = topInset
    }

    init(fountain: Fountain, night: Bool = false, topInset: CGFloat = 0) {
        self.init(spec: FountainPlateSpec(fountain), night: night, topInset: topInset)
    }

    var body: some View {
        Canvas { context, size in
            FountainPlateDrawing.draw(spec, night: night, topInset: topInset, in: context, size: size)
        }
        .accessibilityHidden(true)
    }
}

extension FountainPlateSpec {
    /// A fountain's plate depends on who it is and where, never on its water.
    init(_ fountain: Fountain) {
        self.init(id: fountain.id, kind: fountain.kind, zone: fountain.neighbourhood)
    }
}

/// The inks of one pairing, by day or night.
struct PlateInks {
    var sky: Color
    var sun: Color
    var dot: Color
    var ground: Color
    var stripe: Color
    var rule: Color
    /// The motif colours for the chequered diamond and the bands.
    var motifA: Color
    var motifB: Color

    static func of(_ pairing: PlatePairing, night: Bool) -> PlateInks {
        if night {
            return PlateInks(
                sky: Palette.notte, sun: Palette.luna, dot: Palette.seccaNotte,
                ground: Palette.notteChiara, stripe: Palette.correnteNotte, rule: Palette.carta,
                motifA: Palette.notteChiara, motifB: Palette.salviaScura
            )
        }
        switch pairing {
        case .daylight:
            return PlateInks(
                sky: Palette.carta, sun: Palette.sole, dot: Palette.rosso,
                ground: Palette.facciata, stripe: Palette.blu, rule: Palette.inchiostro,
                motifA: Palette.cartaScura, motifB: Palette.salvia
            )
        case .gold:
            return PlateInks(
                sky: Palette.sole, sun: Palette.rosso, dot: Palette.blu,
                ground: Palette.cartaScura, stripe: Palette.blu, rule: Palette.inchiostro,
                motifA: Palette.carta, motifB: Palette.rosso
            )
        case .river:
            return PlateInks(
                sky: Palette.blu, sun: Palette.carta, dot: Palette.sole,
                ground: Palette.carta, stripe: Palette.blu, rule: Palette.inchiostro,
                motifA: Palette.cartaChiara, motifB: Palette.sole
            )
        case .ochre:
            return PlateInks(
                sky: Palette.facciata, sun: Palette.rosso, dot: Palette.blu,
                ground: Palette.inchiostro, stripe: Palette.sole, rule: Palette.inchiostro,
                motifA: Palette.carta, motifB: Palette.sole
            )
        case .brick:
            return PlateInks(
                sky: Palette.rosso, sun: Palette.sole, dot: Palette.carta,
                ground: Palette.inchiostro, stripe: Palette.sole, rule: Palette.inchiostro,
                motifA: Palette.facciata, motifB: Palette.inchiostro
            )
        }
    }
}

enum FountainPlateDrawing {
    /// Share of the plate's height the ground takes.
    static let groundShare: CGFloat = 0.2
    /// Share of the plate's height the subject takes.
    static let subjectShare: CGFloat = 0.78

    static func draw(_ spec: FountainPlateSpec, night: Bool, topInset: CGFloat = 0, in context: GraphicsContext, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let inks = PlateInks.of(spec.pairing, night: night)
        let w = size.width, h = size.height
        let groundTop = h * (1 - groundShare)
        let line = max(1.2, h * 0.012)
        var ctx = context
        ctx.clip(to: Path(CGRect(origin: .zero, size: size)))

        // Sky.
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(inks.sky))

        // The subject's own place, which the night sun follows. A wide basin is
        // scaled down so it never takes more than about half the width.
        let resolved = ctx.resolve(Image(spec.assetName).interpolation(.high))
        let aspect = resolved.size.height > 0 ? resolved.size.width / resolved.size.height : 0.4
        // The sky the sun and the dot may use, below any inset.
        func skyY(_ fraction: Double) -> CGFloat { topInset + CGFloat(fraction) * (groundTop - topInset) }
        let subjectHeight = min(h * subjectShare, w * 0.5 / max(aspect, 0.1))
        let subjectBase = groundTop + h * groundShare * 0.42
        let subjectCentre = w * spec.subjectX

        // Geometric motifs sit behind everything but the sky.
        switch spec.backdrop {
        case .checker: drawChecker(spec, inks, in: ctx, size: size, groundTop: groundTop)
        case .bands: drawBands(spec, inks, in: ctx, size: size)
        case .landmark: break
        }

        // The sun. At night it is the moon, and it moves behind the subject so the
        // black head always has a light ground to stand against.
        let radius = h * spec.sunRadius
        let sun: CGPoint
        let sunRadius: CGFloat
        if night {
            sun = CGPoint(x: subjectCentre, y: subjectBase - subjectHeight * 0.72)
            sunRadius = max(radius, h * 0.2)
        } else {
            sun = CGPoint(x: w * spec.sunX, y: skyY(spec.sunY * 1.4))
            sunRadius = radius
        }
        ctx.fill(Path(ellipseIn: CGRect(x: sun.x - sunRadius, y: sun.y - sunRadius, width: sunRadius * 2, height: sunRadius * 2)),
                 with: .color(inks.sun))

        // The red dot.
        let dot = h * spec.dotRadius
        let dotCentre = skyY(spec.dotY * 1.5)
        ctx.fill(Path(ellipseIn: CGRect(x: w * spec.dotX - dot, y: dotCentre - dot, width: dot * 2, height: dot * 2)),
                 with: .color(inks.dot))

        // The landmark, standing on the ground line.
        if case let .landmark(landmark) = spec.backdrop {
            drawLandmark(landmark, spec, night: night, in: ctx, size: size, groundTop: groundTop)
        }

        // The ground: a flat band, a heavy rule on top of it and a few thin stripes.
        ctx.fill(Path(CGRect(x: 0, y: groundTop, width: w, height: h - groundTop)), with: .color(inks.ground))
        ctx.fill(Path(CGRect(x: 0, y: groundTop, width: w, height: line * 1.6)), with: .color(inks.rule))
        let bandArea = h - groundTop - line * 1.6
        let pitch = bandArea / CGFloat(spec.stripes * 2 + 1)
        for i in 0 ..< spec.stripes {
            let y = groundTop + line * 1.6 + pitch * (CGFloat(i * 2) + 1.5)
            ctx.fill(Path(CGRect(x: 0, y: y, width: w, height: pitch * 0.8)), with: .color(inks.stripe))
        }

        // The fountain: a printed plate, upright, standing on the ground.
        drawSubject(spec, resolved, in: ctx, centre: subjectCentre, base: subjectBase, height: subjectHeight)
    }

    // MARK: Subject

    private static func drawSubject(
        _ spec: FountainPlateSpec, _ resolved: GraphicsContext.ResolvedImage,
        in context: GraphicsContext, centre: CGFloat, base: CGFloat, height: CGFloat
    ) {
        var ctx = context
        guard resolved.size.height > 0 else { return }
        let width = height * resolved.size.width / resolved.size.height
        if spec.mirrored {
            ctx.translateBy(x: centre, y: 0)
            ctx.scaleBy(x: -1, y: 1)
            ctx.translateBy(x: -centre, y: 0)
        }
        ctx.draw(resolved, in: CGRect(x: centre - width / 2, y: base - height, width: width, height: height))
    }

    // MARK: Landmarks

    private static func drawLandmark(
        _ landmark: TurinLandmark, _ spec: FountainPlateSpec, night: Bool,
        in context: GraphicsContext, size: CGSize, groundTop: CGFloat
    ) {
        let palette = SkylinePalette.of(night: night)
        let h = size.height, w = size.width
        let available = groundTop - h * 0.08
        switch landmark {
        case .alps, .arcades, .bridge:
            // Wide things run across the whole plate, tiled when one is not enough.
            let height = available * (landmark == .alps ? 0.62 : 0.42) * spec.backdropScale
            let tile = height * landmark.aspect
            let count = max(1, Int((w / tile).rounded(.up)))
            let total = tile * CGFloat(count)
            let start = (w - total) / 2
            for i in 0 ..< count {
                landmark.draw(in: context, rect: CGRect(x: start + tile * CGFloat(i), y: groundTop - height, width: tile, height: height), palette: palette)
            }
        default:
            let tall = landmark == .mole ? 1.0 : 0.72
            var height = available * tall * spec.backdropScale
            var width = height * landmark.aspect
            // A broad building must still leave room for the fountain.
            if width > w * 0.62 { width = w * 0.62; height = width / landmark.aspect }
            let x = min(max(w * spec.backdropX - width / 2, -width * 0.08), w - width * 0.92)
            landmark.draw(in: context, rect: CGRect(x: x, y: groundTop - height, width: width, height: height), palette: palette)
        }
    }

    // MARK: Motifs

    private static func drawChecker(
        _ spec: FountainPlateSpec, _ inks: PlateInks, in context: GraphicsContext, size: CGSize, groundTop: CGFloat
    ) {
        // The poster's diamond: a 3 × 3 grid turned 45 degrees, big enough to read as
        // a shape rather than a texture.
        let side = min(size.width * 0.9, groundTop * 1.15) / sqrt(2) * 1.0
        let cell = side / 3
        var ctx = context
        ctx.translateBy(x: size.width * spec.backdropX, y: groundTop * 0.62)
        ctx.rotate(by: .degrees(45))
        for row in 0 ..< 3 {
            for column in 0 ..< 3 {
                let colour: Color = (row == 1 && column == 1) ? inks.dot
                    : (row + column).isMultiple(of: 2) ? inks.motifA : inks.motifB
                ctx.fill(Path(CGRect(x: -side / 2 + CGFloat(column) * cell, y: -side / 2 + CGFloat(row) * cell, width: cell, height: cell)),
                         with: .color(colour))
            }
        }
        ctx.stroke(Path(CGRect(x: -side / 2, y: -side / 2, width: side, height: side)),
                   with: .color(inks.rule), lineWidth: max(1.2, size.height * 0.01))
    }

    private static func drawBands(
        _ spec: FountainPlateSpec, _ inks: PlateInks, in context: GraphicsContext, size: CGSize
    ) {
        let bandWidth = size.width * 0.11
        let gap = bandWidth * 0.6
        let x0 = size.width * spec.backdropX - (bandWidth * 3 + gap * 2) / 2
        for i in 0 ..< 3 {
            let colour = i == 1 ? inks.motifB : inks.motifA
            context.fill(Path(CGRect(x: x0 + CGFloat(i) * (bandWidth + gap), y: 0, width: bandWidth, height: size.height)), with: .color(colour))
        }
    }
}

// MARK: - Drawing a landmark into somebody else's canvas

extension TurinLandmark {
    /// Draws the building into `rect` of an existing context, standing on its bottom
    /// edge, so a composed scene is one canvas and not a stack of them.
    func draw(in context: GraphicsContext, rect: CGRect, palette: SkylinePalette) {
        var c = context
        c.translateBy(x: rect.minX, y: rect.minY)
        func go<D: LandmarkDrawing>(_ drawing: D) {
            var d = Draw(c, box: D.box, size: rect.size)
            drawing.draw(&d, palette)
        }
        switch self {
        case .mole: go(MoleDrawing())
        case .superga: go(SupergaDrawing())
        case .duomo: go(DuomoDrawing())
        case .granMadre: go(GranMadreDrawing())
        case .palazzoMadama: go(PalazzoMadamaDrawing())
        case .portaPalatina: go(PortaPalatinaDrawing())
        case .portaNuova: go(PortaNuovaDrawing())
        case .sanCarlo: go(SanCarloDrawing())
        case .rider: go(RiderDrawing())
        case .cappuccini: go(CappucciniDrawing())
        case .bridge: go(BridgeDrawing())
        case .arcades: go(ArcadesDrawing())
        case .alps: go(AlpsDrawing(wide: true, seed: 1))
        case .bull: go(BullProfileDrawing())
        }
    }
}
