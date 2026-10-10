import SwiftUI

/// The Mole Antonelliana, built the way the poster builds it: a colonnade on a dark
/// slab, a band of arched windows, a tall ribbed vault with a lit side and a
/// near-black side, a dark gallery, two lantern stages, and a spire so long that
/// it is almost half the building.
///
/// It is the one landmark that is a portrait rather than a mark. You can raise
/// your eyes and find it from anywhere in the city, which is the same job the
/// compass does.
struct MoleDrawing: LandmarkDrawing {
    static let box = CGSize(width: 100, height: 260)

    func draw(_ d: inout Draw, _ p: SkylinePalette) {
        let cx: CGFloat = 50

        // Slab: the low dark roofs the colonnade stands on.
        d.poly([(2, 260), (8, 247), (92, 247), (98, 260)], p.slab)

        // Colonnade: stone with the dark gaps between the columns.
        d.rect(6, 233, 88, 14, p.stone)
        d.colonnade(7, 235, 86, 11, count: 29, gapFraction: 0.5, p.ink)
        d.rect(50, 233, 44, 14, p.shade)

        // Entablature, a dark band under the windows.
        d.rect(4, 224, 92, 9, p.domeShade)
        d.rect(4, 224, 92, 1.6, p.stone)
        d.rect(50, 224, 46, 9, p.shade)

        // Window band: cream with small arched openings.
        d.rect(10, 208, 80, 16, p.stone)
        d.archRow(12, 211, 76, 9, count: 14, fraction: 0.5, p.ink)
        d.rect(50, 208, 40, 16, p.shade)
        d.rect(9, 205, 82, 3.4, p.domeShade)

        // The vault: a bell-shaped pavilion dome, lit on the left and dark on the right.
        let left = vault(cx: cx, side: -1)
        let right = vault(cx: cx, side: 1)
        d.fill(left, p.dome)
        d.fill(right, p.domeShade)
        d.fill(right, p.shade)
        for k in -5 ... 5 {
            let kk = CGFloat(k)
            let base = cx + kk * 6.6
            let top = cx + kk * 3.0
            let color = k < 0 ? p.ink.opacity(0.32) : p.stone.opacity(0.20)
            d.line(CGPoint(x: base, y: 205), CGPoint(x: top, y: 146), color, width: 0.8)
        }

        // Gallery: a dark drum, a pale ledge, and a balcony rail.
        d.rect(33, 138, 34, 9, p.domeShade)
        d.rect(31, 135, 38, 3.6, p.stone)
        d.rect(50, 135, 19, 3.6, p.shade)
        d.rect(33, 131.4, 34, 1.4, p.ink)

        // Lower lantern: a colonnaded stage under a gabled roof.
        d.rect(39, 116, 22, 15.4, p.stone)
        d.colonnade(40, 118, 20, 12, count: 7, gapFraction: 0.5, p.ink)
        d.rect(50, 116, 11, 15.4, p.shade)
        d.poly([(50, 106), (63, 116), (37, 116)], p.domeShade)
        d.poly([(50, 106), (63, 116), (50, 116)], p.shade)

        // Upper lantern, narrower still.
        d.rect(45, 90, 10, 11, p.stone)
        d.colonnade(45.6, 91.4, 8.8, 8.6, count: 4, gapFraction: 0.5, p.ink)
        d.rect(50, 90, 5, 11, p.shade)
        d.rect(43.4, 87.6, 13.2, 2.6, p.stone)
        d.poly([(50, 79), (56, 87.6), (44, 87.6)], p.domeShade)

        // Spire: a needle with two collars and the star.
        d.poly([(50, 7), (51.5, 79.5), (48.5, 79.5)], p.silhouette)
        d.rect(48.3, 60, 3.4, 2.2, p.silhouette)
        d.rect(48.8, 40, 2.4, 1.8, p.silhouette)
        d.star(50, 4.2, 4.2, p.silhouette)
    }

    /// One half of the vault's silhouette, from the apex down to the window band.
    private func vault(cx: CGFloat, side: CGFloat) -> Path {
        var path = Path()
        let baseY: CGFloat = 205, topY: CGFloat = 147
        let baseHalf: CGFloat = 39, topHalf: CGFloat = 17
        path.move(to: CGPoint(x: cx, y: topY))
        path.addLine(to: CGPoint(x: cx + side * topHalf, y: topY))
        path.addCurve(
            to: CGPoint(x: cx + side * baseHalf, y: baseY),
            control1: CGPoint(x: cx + side * (topHalf + 8), y: topY + 6),
            control2: CGPoint(x: cx + side * baseHalf, y: baseY - 30)
        )
        path.addLine(to: CGPoint(x: cx, y: baseY))
        path.closeSubpath()
        return path
    }
}

/// The Mole Antonelliana as a view.
struct MoleAntonelliana: View {
    var night = false
    var body: some View { DrawnLandmark(MoleDrawing(), palette: .of(night: night)) }
}
