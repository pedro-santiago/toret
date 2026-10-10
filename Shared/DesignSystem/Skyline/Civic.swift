import SwiftUI

// The city's stone: palaces, a Roman gate, a station, a bridge and a bronze rider.

// MARK: - Palazzo Madama

/// Palazzo Madama: Juvarra's two-storey façade of arches and columns, crowned with a
/// balustrade of statues, between the two old towers of the castle behind it.
struct PalazzoMadamaDrawing: LandmarkDrawing {
    static let box = CGSize(width: 160, height: 90)

    func draw(_ d: inout Draw, _ p: SkylinePalette) {
        // Wings.
        for x in [24.0, 104.0] {
            d.rect(x, 42, 32, 44, p.stone)
            d.windowRow(x + 2, 48, 28, 7, count: 4, fraction: 0.45, p.ink)
            d.windowRow(x + 2, 62, 28, 7, count: 4, fraction: 0.45, p.ink)
            d.windowRow(x + 2, 76, 28, 7, count: 4, fraction: 0.45, p.ink)
            d.rect(x, 39, 32, 3.4, p.roof)
        }
        d.rect(80, 42, 56, 44, p.shade)

        // Towers.
        for (x, shaded) in [(4.0, false), (136.0, true)] {
            d.rect(x, 24, 20, 62, p.facade)
            d.arch(x + 6, 32, 8, 12, p.ink)
            d.windowRow(x + 3, 54, 14, 7, count: 2, fraction: 0.5, p.ink)
            d.windowRow(x + 3, 68, 14, 7, count: 2, fraction: 0.5, p.ink)
            d.rect(x - 2, 21, 24, 3.4, p.stone)
            d.poly([(x + 10, 6), (x + 23, 21), (x - 3, 21)], p.roof)
            d.poly([(x + 10, 6), (x + 23, 21), (x + 10, 21)], p.shade)
            if shaded { d.rect(x, 24, 20, 62, p.shade) }
        }

        // Central façade: arched windows between pilasters, a column order above,
        // a balustrade, and statues on the skyline.
        d.rect(52, 24, 56, 62, p.stone)
        d.archRow(55, 52, 50, 34, count: 4, fraction: 0.62, p.ink)
        d.rect(50, 47, 60, 3.6, p.stone)
        d.hline(50, 50.6, 60, p.ink.opacity(0.4), width: 0.9)
        d.colonnade(54, 28, 52, 18, count: 9, gapFraction: 0.42, p.ink)
        d.rect(50, 21, 60, 3.8, p.stone)
        d.windowRow(52, 16.6, 56, 4.4, count: 18, fraction: 0.4, p.silhouette.opacity(0.7))
        for x in [56.0, 68, 80, 92, 104] {
            d.ellipse(x, 12.5, 1.6, 1.9, p.silhouette)
            d.rect(x - 1.1, 14, 2.2, 3, p.silhouette)
        }
        d.rect(80, 21, 30, 65, p.shade)
        d.rect(46, 86, 68, 4, p.stone)
    }
}

struct PalazzoMadama: View {
    var night = false
    var body: some View { DrawnLandmark(PalazzoMadamaDrawing(), palette: .of(night: night)) }
}

// MARK: - Porta Palatina

/// The Roman gate: two sixteen-sided brick towers, two great arches for carts,
/// two small ones for people, and two galleries of arched windows above.
struct PortaPalatinaDrawing: LandmarkDrawing {
    static let box = CGSize(width: 120, height: 90)

    func draw(_ d: inout Draw, _ p: SkylinePalette) {
        // The curtain wall between the towers.
        d.rect(32, 34, 56, 56, p.brick)
        d.rect(32, 32, 56, 2.6, p.stone)
        d.archRow(35, 38, 50, 9, count: 8, fraction: 0.5, p.ink)
        d.rect(32, 48.6, 56, 1.8, p.stone)
        d.archRow(35, 52, 50, 9, count: 8, fraction: 0.5, p.ink)
        d.rect(32, 63, 56, 1.8, p.stone)
        // The four passages: two great arches and two small.
        d.arch(36, 70, 7, 20, p.ink)
        d.arch(46, 66, 11, 24, p.ink)
        d.arch(63, 66, 11, 24, p.ink)
        d.arch(77, 70, 7, 20, p.ink)
        d.rect(60, 32, 28, 58, p.shade)

        // Towers, faceted: three vertical planes, the last in shade.
        for x in [6.0, 86.0] {
            d.rect(x, 14, 28, 76, p.brick)
            d.rect(x + 9, 14, 10, 76, p.brick)
            d.rect(x + 19, 14, 9, 76, p.shade)
            d.rect(x - 1.5, 11, 31, 3.6, p.stone)
            // Crenellation.
            for i in 0 ..< 5 {
                d.rect(x + 1 + CGFloat(i) * 6.2, 6.6, 3.6, 4.6, p.brick)
            }
            for y in [22.0, 40, 58] {
                d.arch(x + 4, y, 5.2, 11, p.ink)
                d.arch(x + 11.4, y, 5.2, 11, p.ink)
                d.arch(x + 18.8, y, 5.2, 11, p.ink)
            }
        }
        d.rect(4, 90, 112, 0.01, p.ink)
    }
}

struct PortaPalatina: View {
    var night = false
    var body: some View { DrawnLandmark(PortaPalatinaDrawing(), palette: .of(night: night)) }
}

// MARK: - Porta Nuova

/// Porta Nuova station: a grand hall of three tall arches between two arcaded wings.
struct PortaNuovaDrawing: LandmarkDrawing {
    static let box = CGSize(width: 150, height: 70)

    func draw(_ d: inout Draw, _ p: SkylinePalette) {
        for x in [4.0, 104.0] {
            d.rect(x, 32, 42, 38, p.facade)
            d.rect(x - 1, 28, 44, 4.6, p.roof)
            d.windowRow(x + 3, 37, 36, 7, count: 6, fraction: 0.42, p.ink)
            d.archRow(x + 2, 52, 38, 18, count: 5, fraction: 0.56, p.ink)
        }
        d.rect(75, 28, 71, 42, p.shade)
        d.rect(46, 14, 58, 56, p.stone)
        d.rect(44, 8, 62, 6, p.domeShade)
        d.rect(44, 8, 62, 1.6, p.stone)
        d.archRow(50, 22, 50, 48, count: 3, fraction: 0.74, p.ink)
        d.windowRow(50, 17, 50, 3, count: 10, fraction: 0.5, p.ink.opacity(0.6))
        d.rect(75, 14, 29, 56, p.shade)
    }
}

struct PortaNuovaStation: View {
    var night = false
    var body: some View { DrawnLandmark(PortaNuovaDrawing(), palette: .of(night: night)) }
}

// MARK: - Caval ëd Brons

/// The bronze horse and rider of Piazza San Carlo, on its plinth: a silhouette
/// standing against the sky, as the poster has it above the rooftops.
struct RiderDrawing: LandmarkDrawing {
    static let box = CGSize(width: 70, height: 90)

    func draw(_ d: inout Draw, _ p: SkylinePalette) {
        // Plinth.
        d.rect(4, 80, 62, 10, p.stone)
        d.rect(11, 56, 48, 24, p.stone)
        d.rect(8, 52, 54, 4.6, p.stone)
        d.rect(18, 62, 34, 12, p.ink.opacity(0.32))
        d.rect(35, 52, 31, 38, p.shade)

        let s = p.silhouette
        // Horse: barrel, neck, head, four legs, tail.
        d.ellipse(32, 38, 16, 8, s)
        d.poly([(41, 34), (47, 15), (54, 13), (50, 33)], s)
        d.poly([(47, 16), (54, 12), (60, 19), (55, 22), (50, 21)], s)
        d.poly([(50, 12), (52, 7), (54, 12)], s)
        d.poly([(40, 42), (44, 42), (45, 54), (41, 54)], s)
        d.poly([(35, 43), (39, 43), (38, 54), (34, 54)], s)
        d.poly([(16, 40), (21, 40), (19, 54), (15, 54)], s)
        d.poly([(22, 42), (26, 42), (25, 54), (21, 54)], s)
        d.poly([(17, 32), (13, 36), (8, 52), (12, 51), (15, 40)], s)
        // Rider: cloak, torso, head and hat, and the sword.
        d.poly([(24, 16), (20, 34), (28, 31), (30, 17)], s)
        d.poly([(27, 14), (33, 14), (35, 31), (26, 31)], s)
        d.ellipse(30, 10, 3.4, 3.8, s)
        d.poly([(26.4, 8), (33.6, 8), (31, 2.6), (28, 2.6)], s)
        d.line(CGPoint(x: 33, y: 20), CGPoint(x: 46, y: 8), s, width: 1.5)
    }
}

struct CavalloDiBronzo: View {
    var night = false
    var body: some View { DrawnLandmark(RiderDrawing(), palette: .of(night: night)) }
}

// MARK: - Ponte Vittorio Emanuele I

/// The stone bridge over the Po, with the river running under it in the poster's
/// blue stripes.
struct BridgeDrawing: LandmarkDrawing {
    static let box = CGSize(width: 160, height: 70)

    func draw(_ d: inout Draw, _ p: SkylinePalette) {
        // River stripes along the foot.
        d.rect(0, 48, 160, 22, p.water)
        for y in [53.5, 59.0, 64.5] { d.rect(0, y, 160, 1.6, p.stone.opacity(0.9)) }

        // Deck and body.
        d.rect(0, 14, 160, 34, p.stone)
        d.rect(0, 11, 160, 3.4, p.stone)
        d.rect(0, 11, 160, 1.2, p.ink.opacity(0.5))
        // Parapet posts.
        d.windowRow(2, 15, 156, 4, count: 40, fraction: 0.5, p.ink.opacity(0.4))
        // Three segmental arches, the water showing through them.
        for cx in [28.0, 80, 132] {
            let w: CGFloat = 40
            var arch = Path()
            arch.move(to: CGPoint(x: cx - w / 2, y: 48))
            arch.addQuadCurve(to: CGPoint(x: cx + w / 2, y: 48), control: CGPoint(x: cx, y: 12))
            arch.closeSubpath()
            d.fill(arch, p.ink)
            var water = Path()
            water.move(to: CGPoint(x: cx - w / 2 + 6, y: 48))
            water.addQuadCurve(to: CGPoint(x: cx + w / 2 - 6, y: 48), control: CGPoint(x: cx, y: 26))
            water.closeSubpath()
            d.fill(water, p.water)
        }
        d.rect(80, 11, 80, 37, p.shade)
    }
}

struct PoBridge: View {
    var night = false
    var body: some View { DrawnLandmark(BridgeDrawing(), palette: .of(night: night)) }
}
