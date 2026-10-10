import SwiftUI

/// A thin run of Turin along the foot or the head of a plate: arcades in front, the
/// landmarks behind them, standing on one line.
///
/// This is for tight places, a list footer or the edge under a title. The big
/// poster scenes are bitmaps and live elsewhere; this stays a few vector shapes so
/// it is cheap, crisp at any width and recolours for the night plate.
struct TurinSkyline: View {
    enum Style {
        /// Arcades with landmarks behind, ~110 pt tall, in full colour.
        case strip
        /// A low single-colour silhouette, ~48 pt tall, for behind a title.
        case horizon
    }

    var style: Style = .strip
    var night = false
    /// A landmark to put the sun behind. Added to the skyline if it is not already there.
    var highlight: TurinLandmark?
    /// Chooses which landmarks appear and how they are spaced. The same seed always
    /// draws the same city.
    var seed = 1
    /// Horizon only: the silhouette's colour. Defaults to a pale ink.
    var tint: Color?

    var body: some View {
        switch style {
        case .strip: strip.frame(height: 110)
        case .horizon: horizon.frame(height: 48)
        }
    }

    // MARK: Strip

    private struct Placed: Identifiable {
        let landmark: TurinLandmark
        let x: CGFloat
        let height: CGFloat
        var id: String { landmark.id }
    }

    /// The landmarks in the strip, as fractions of its width and of the ground line.
    private func placements() -> [Placed] {
        var rng = SkylineRandom(seed: seed)
        var items: [(TurinLandmark, CGFloat, CGFloat)] = [
            (.duomo, 0.14, 0.62), (.cappuccini, 0.38, 0.42), (.mole, 0.72, 1.0),
        ]
        if rng.int(in: 0 ... 1) == 0 { items.append((.superga, 0.90, 0.5)) }
        else { items.append((.portaPalatina, 0.90, 0.46)) }
        if let highlight, !items.contains(where: { $0.0 == highlight }) {
            items[1] = (highlight, 0.38, items[1].2 + 0.12)
        }
        return items.map { landmark, x, h in
            Placed(landmark: landmark, x: x + rng.value(in: -0.03 ... 0.03), height: h)
        }
    }

    private var strip: some View {
        let p = SkylinePalette.of(night: night)
        return GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let arcadeHeight = h * 0.42
            let ground = h - arcadeHeight * 0.62
            ZStack(alignment: .topLeading) {
                ForEach(placements()) { item in
                    let height = ground * item.height
                    let width = height * item.landmark.aspect
                    ZStack {
                        if item.landmark == highlight {
                            Circle().fill(p.sun)
                                .frame(width: height * 0.95, height: height * 0.95)
                                .offset(y: -height * 0.05)
                        }
                        item.landmark.view(night: night).frame(width: width, height: height)
                    }
                    .frame(width: max(width, height * 0.95), height: height)
                    .position(x: item.x * w, y: ground - height / 2)
                }

                // Arcades in front, tiled to the width with a different seed each time.
                let tile = arcadeHeight * ArcadesDrawing.aspect
                HStack(spacing: 0) {
                    ForEach(0 ..< max(1, Int((w / tile).rounded(.up))), id: \.self) { index in
                        TurinArcades(night: night, seed: seed + index * 11)
                            .frame(width: tile, height: arcadeHeight)
                    }
                }
                .frame(width: w, alignment: .leading)
                .clipped()
                .offset(y: h - arcadeHeight)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Horizon

    private var horizon: some View {
        let colour = tint ?? (night ? Palette.carta.opacity(0.16) : Palette.inchiostro.opacity(0.14))
        let palette = SkylinePalette.mono(colour)
        var rng = SkylineRandom(seed: seed)
        let cast: [(TurinLandmark, CGFloat)] = [
            (.duomo, 0.80), (.arcades, 0.34), (.mole, 1.0), (.arcades, 0.30),
            (.superga, 0.58), (.arcades, 0.36), (.cappuccini, 0.5), (.arcades, 0.32),
        ]
        let order = rng.int(in: 0 ... 1) == 0 ? cast : Array(cast.reversed())
        return GeometryReader { proxy in
            let h = proxy.size.height
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(order.enumerated()), id: \.offset) { _, item in
                    item.0.view(palette: palette).frame(height: h * item.1)
                }
            }
            .frame(width: proxy.size.width, height: h, alignment: .bottomLeading)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}
