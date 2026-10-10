import SwiftUI

// The domes of Turin. Each is one flat drawing in its own box, standing on the
// bottom edge, so a row of them shares a ground line.

// MARK: - Superga

/// The Basilica di Superga, on its hill across the Po: a pedimented portico, a
/// drum and a green dome between two bell towers.
struct SupergaDrawing: LandmarkDrawing {
    static let box = CGSize(width: 160, height: 100)

    func draw(_ d: inout Draw, _ p: SkylinePalette) {
        // The hill.
        var hill = Path()
        hill.move(to: CGPoint(x: 0, y: 100))
        hill.addLine(to: CGPoint(x: 0, y: 86))
        hill.addQuadCurve(to: CGPoint(x: 80, y: 72), control: CGPoint(x: 30, y: 72))
        hill.addQuadCurve(to: CGPoint(x: 160, y: 88), control: CGPoint(x: 130, y: 72))
        hill.addLine(to: CGPoint(x: 160, y: 100))
        hill.closeSubpath()
        d.fill(hill, p.dome)
        var hillShade = Path()
        hillShade.move(to: CGPoint(x: 80, y: 72))
        hillShade.addQuadCurve(to: CGPoint(x: 160, y: 88), control: CGPoint(x: 130, y: 72))
        hillShade.addLine(to: CGPoint(x: 160, y: 100))
        hillShade.addLine(to: CGPoint(x: 80, y: 100))
        hillShade.closeSubpath()
        d.fill(hillShade, p.domeShade)

        // Low wings joining the towers to the portico.
        d.rect(30, 56, 100, 17, p.stone)
        d.windowRow(34, 60, 92, 7, count: 12, fraction: 0.4, p.ink)
        d.rect(80, 56, 50, 17, p.shade)

        // Drum and dome, behind the portico.
        d.rect(62, 24, 36, 22, p.stone)
        d.archRow(65, 28, 30, 10, count: 4, fraction: 0.5, p.ink)
        d.rect(80, 24, 18, 22, p.shade)
        d.dome(80, 24, 19, 16, p.dome)
        d.domeRight(80, 24, 19, 16, p.domeShade)
        d.rect(77.4, 3, 5.2, 6, p.stone)
        d.poly([(80, 0), (83.4, 3), (76.6, 3)], p.domeShade)

        // Bell towers.
        for (x, shaded) in [(26.0, false), (116.0, true)] {
            d.rect(x, 26, 18, 47, p.stone)
            d.arch(x + 5, 34, 8, 14, p.ink)
            d.rect(x + 2, 56, 14, 3, p.ink.opacity(0.22))
            d.rect(x - 2, 23, 22, 3.4, p.stone)
            d.dome(x + 9, 23, 9, 8, p.domeShade)
            d.rect(x + 8.6, 11, 0.9, 5, p.silhouette)
            d.rect(x + 9, 26, 9, 47, p.shade)
            if shaded { d.rect(x + 9, 23, 11, 3.4, p.shade) }
        }

        // Portico: pediment over a row of columns, on a flight of steps.
        d.poly([(80, 38), (110, 49), (50, 49)], p.stone)
        d.poly([(80, 38), (110, 49), (80, 49)], p.shade)
        d.rect(52, 49, 56, 3.4, p.stone)
        d.rect(54, 52, 52, 21, p.stone)
        d.colonnade(55, 53, 50, 19, count: 8, gapFraction: 0.42, p.ink)
        d.rect(80, 49, 28, 24, p.shade)
        d.rect(50, 73, 60, 2.6, p.stone)
    }
}

struct SupergaBasilica: View {
    var night = false
    var body: some View { DrawnLandmark(SupergaDrawing(), palette: .of(night: night)) }
}

// MARK: - Cathedral bell tower and the Guarini dome

/// The Duomo's bell tower, with Guarini's dome of the Cappella della Sindone behind
/// it: a pile of arched tiers rising to a pointed cone.
struct DuomoDrawing: LandmarkDrawing {
    static let box = CGSize(width: 110, height: 130)

    func draw(_ d: inout Draw, _ p: SkylinePalette) {
        // Cathedral roofline.
        d.rect(0, 116, 110, 14, p.stone)
        d.windowRow(4, 120, 102, 6, count: 14, fraction: 0.4, p.ink)
        d.rect(55, 116, 55, 14, p.shade)

        // Guarini's dome: a drum of tall windows, then four tiers of arches,
        // each narrower than the last, and a cone with a ball on it.
        d.rect(10, 92, 44, 24, p.stone)
        d.archRow(13, 96, 38, 17, count: 5, fraction: 0.5, p.ink)
        d.rect(32, 92, 22, 24, p.shade)
        let tiers: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, n: Int)] = [
            (15, 82, 34, 10, 6), (19, 73, 26, 9, 5), (23, 65, 18, 8, 4), (26, 58, 12, 7, 3),
        ]
        for tier in tiers {
            d.rect(tier.x, tier.y, tier.w, tier.h, p.stone)
            d.archRow(tier.x + 1.2, tier.y + 2, tier.w - 2.4, tier.h - 2, count: tier.n, fraction: 0.5, p.ink)
            d.rect(32, tier.y, tier.w / 2 + tier.x - 32 + 0.01, tier.h, p.shade)
        }
        d.poly([(32, 34), (39, 58), (25, 58)], p.dome)
        d.poly([(32, 34), (39, 58), (32, 58)], p.domeShade)
        d.line(CGPoint(x: 28.5, y: 48), CGPoint(x: 35.5, y: 48), p.ink.opacity(0.4), width: 0.8)
        d.line(CGPoint(x: 27, y: 53), CGPoint(x: 37, y: 53), p.ink.opacity(0.4), width: 0.8)
        d.ellipse(32, 31.5, 2.4, 2.4, p.silhouette)
        d.rect(31.5, 22, 1, 7, p.silhouette)
        d.rect(29.6, 24.2, 4.8, 1, p.silhouette)

        // The bell tower: a shaft in storeys, a belfry, and Juvarra's cupola.
        d.rect(68, 56, 28, 60, p.stone)
        for y in [66.0, 82, 98] {
            d.rect(68, y, 28, 1.4, p.ink.opacity(0.35))
        }
        d.rect(73, 70, 4, 8, p.ink)
        d.rect(83, 70, 4, 8, p.ink)
        d.rect(73, 86, 4, 8, p.ink)
        d.rect(83, 86, 4, 8, p.ink)
        d.rect(82, 56, 14, 60, p.shade)
        // Belfry.
        d.rect(66, 38, 32, 18, p.stone)
        d.archRow(69, 41, 26, 15, count: 2, fraction: 0.62, p.ink)
        d.rect(82, 38, 16, 18, p.shade)
        d.rect(64, 35, 36, 3.6, p.stone)
        // Cupola: a stepped octagon under a dome with a lantern and a cross.
        d.rect(70, 28, 24, 7, p.stone)
        d.rect(82, 28, 12, 7, p.shade)
        d.dome(82, 28, 9, 9, p.dome)
        d.domeRight(82, 28, 9, 9, p.domeShade)
        d.rect(80.4, 14, 3.2, 6, p.stone)
        d.rect(81.5, 6, 1, 8, p.silhouette)
        d.rect(79.8, 8.4, 4.4, 1, p.silhouette)
    }
}

struct DuomoSindone: View {
    var night = false
    var body: some View { DrawnLandmark(DuomoDrawing(), palette: .of(night: night)) }
}

// MARK: - Gran Madre di Dio

/// The Gran Madre, across the bridge: a Pantheon-like pronaos on a long flight of
/// steps, a drum and a shallow dome, and a seated statue at each side.
struct GranMadreDrawing: LandmarkDrawing {
    static let box = CGSize(width: 140, height: 100)

    func draw(_ d: inout Draw, _ p: SkylinePalette) {
        // Drum and shallow dome.
        d.rect(46, 20, 48, 34, p.stone)
        d.windowRow(50, 26, 40, 10, count: 5, fraction: 0.45, p.ink)
        d.rect(70, 20, 24, 34, p.shade)
        d.dome(70, 20, 27, 12, p.dome)
        d.domeRight(70, 20, 27, 12, p.domeShade)
        d.rect(67, 4, 6, 5, p.stone)
        d.poly([(70, 0), (73.6, 4), (66.4, 4)], p.domeShade)

        // Pronaos: pediment, frieze, six columns.
        d.poly([(70, 36), (108, 48), (32, 48)], p.stone)
        d.poly([(70, 36), (108, 48), (70, 48)], p.shade)
        d.rect(34, 48, 72, 4, p.stone)
        d.rect(34, 52, 72, 28, p.stone)
        d.colonnade(36, 52, 68, 28, count: 6, gapFraction: 0.48, p.ink)
        d.rect(70, 48, 36, 32, p.shade)

        // The steps, widest at the foot.
        for i in 0 ..< 5 {
            let y = 80 + CGFloat(i) * 4
            let w = 76 + CGFloat(i) * 8
            d.rect(70 - w / 2, y, w, 4.2, p.stone)
            d.rect(70, y, w / 2, 4.2, p.shade)
            d.hline(70 - w / 2, y, w, p.ink.opacity(0.35), width: 0.8)
        }

        // A statue on a plinth, each side of the stairs.
        for x in [18.0, 122.0] {
            d.rect(x - 6, 86, 12, 14, p.stone)
            d.rect(x, 86, 6, 14, p.shade)
            d.poly([(x - 3.6, 86), (x - 3, 74), (x + 3, 74), (x + 3.6, 86)], p.silhouette)
            d.ellipse(x, 71, 2.6, 3, p.silhouette)
        }
    }
}

struct GranMadreDiDio: View {
    var night = false
    var body: some View { DrawnLandmark(GranMadreDrawing(), palette: .of(night: night)) }
}

// MARK: - San Carlo

/// The twin churches of Piazza San Carlo, San Carlo and Santa Cristina, with the
/// arcaded gap of Via Roma between them.
struct SanCarloDrawing: LandmarkDrawing {
    static let box = CGSize(width: 150, height: 100)

    func draw(_ d: inout Draw, _ p: SkylinePalette) {
        // The arcade between them.
        d.rect(54, 68, 42, 32, p.facade)
        d.rect(54, 63, 42, 5, p.roof)
        d.windowRow(57, 72, 36, 6, count: 5, fraction: 0.45, p.ink)
        d.archRow(56, 84, 38, 16, count: 4, fraction: 0.56, p.ink)
        d.rect(75, 63, 21, 37, p.shade)

        for (x, shaded) in [(12.0, false), (92.0, true)] {
            // Drum and dome behind the façade.
            d.rect(x + 12, 26, 22, 20, p.stone)
            d.archRow(x + 15, 30, 16, 9, count: 3, fraction: 0.5, p.ink)
            d.dome(x + 23, 26, 13, 12, p.dome)
            d.domeRight(x + 23, 26, 13, 12, p.domeShade)
            d.rect(x + 21, 10, 4, 5, p.stone)
            d.rect(x + 22.6, 2, 0.9, 7, p.silhouette)
            d.rect(x + 20.8, 4, 4.4, 0.9, p.silhouette)

            // Façade: pediment over four columns, a doorway between.
            d.poly([(x + 23, 40), (x + 46, 51), (x, 51)], p.stone)
            d.poly([(x + 23, 40), (x + 46, 51), (x + 23, 51)], p.shade)
            d.rect(x, 51, 46, 4, p.stone)
            d.rect(x, 55, 46, 45, p.stone)
            d.colonnade(x + 2, 57, 42, 25, count: 4, gapFraction: 0.4, p.ink)
            d.arch(x + 18, 84, 10, 16, p.ink)
            d.rect(x + 23, 51, 23, 49, p.shade)
            if shaded { d.rect(x, 51, 23, 49, p.shade) }
        }
    }
}

struct SanCarloChurches: View {
    var night = false
    var body: some View { DrawnLandmark(SanCarloDrawing(), palette: .of(night: night)) }
}

// MARK: - Monte dei Cappuccini

/// The little domed church on its hill across the river, with the convent wing
/// beside it and a couple of cypresses.
struct CappucciniDrawing: LandmarkDrawing {
    static let box = CGSize(width: 110, height: 90)

    func draw(_ d: inout Draw, _ p: SkylinePalette) {
        var hill = Path()
        hill.move(to: CGPoint(x: 0, y: 90))
        hill.addLine(to: CGPoint(x: 0, y: 72))
        hill.addQuadCurve(to: CGPoint(x: 55, y: 58), control: CGPoint(x: 20, y: 58))
        hill.addQuadCurve(to: CGPoint(x: 110, y: 76), control: CGPoint(x: 92, y: 58))
        hill.addLine(to: CGPoint(x: 110, y: 90))
        hill.closeSubpath()
        d.fill(hill, p.dome)
        var shade = Path()
        shade.move(to: CGPoint(x: 55, y: 58))
        shade.addQuadCurve(to: CGPoint(x: 110, y: 76), control: CGPoint(x: 92, y: 58))
        shade.addLine(to: CGPoint(x: 110, y: 90))
        shade.addLine(to: CGPoint(x: 55, y: 90))
        shade.closeSubpath()
        d.fill(shade, p.domeShade)

        // Convent wing.
        d.rect(12, 46, 26, 15, p.facade)
        d.rect(10, 43, 30, 3.6, p.roof)
        d.windowRow(14, 50, 22, 6, count: 4, fraction: 0.4, p.ink)

        // Drum and dome.
        d.rect(46, 26, 18, 10, p.stone)
        d.arch(51.5, 28, 7, 8, p.ink)
        d.dome(55, 26, 11, 10, p.dome)
        d.domeRight(55, 26, 11, 10, p.domeShade)
        d.rect(53.4, 11, 3.2, 5, p.stone)
        d.rect(54.6, 3, 0.9, 7, p.silhouette)
        d.rect(52.8, 5, 4.4, 0.9, p.silhouette)

        // Façade with a portico of arches.
        d.poly([(55, 34), (75, 43), (35, 43)], p.stone)
        d.poly([(55, 34), (75, 43), (55, 43)], p.shade)
        d.rect(36, 43, 38, 17, p.stone)
        d.archRow(38, 47, 34, 13, count: 3, fraction: 0.6, p.ink)
        d.rect(55, 43, 19, 17, p.shade)

        // Cypresses.
        for (x, h) in [(86.0, 24.0), (95.0, 18.0)] {
            d.poly([(x, 74 - h), (x + 4, 74), (x - 4, 74)], p.domeShade)
        }
    }
}

struct MonteDeiCappuccini: View {
    var night = false
    var body: some View { DrawnLandmark(CappucciniDrawing(), palette: .of(night: night)) }
}
