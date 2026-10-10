import SwiftUI

// The poster's furniture that needs no type: a dot, a river, a band.

/// The poster's red dot: a small second sun, always off to one side of the thing
/// the screen is about.
struct RedDot: View {
    var size: CGFloat = 28
    var night = false

    var body: some View {
        Circle().fill(SkylinePalette.of(night: night).dot)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The river as thin blue bands with hairlines of stock between them: the quiet
/// cousin of `WaterStripes`, for the foot of a plate where the big river would shout.
struct RiverStripes: View {
    var bands = 4
    var night = false

    var body: some View {
        let p = SkylinePalette.of(night: night)
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(p.water))
            let band = size.height / CGFloat(bands)
            let gap = max(1.5, band * 0.12)
            for i in 1 ..< max(bands, 1) {
                context.fill(
                    Path(CGRect(x: 0, y: band * CGFloat(i) - gap / 2, width: size.width, height: gap)),
                    with: .color(night ? Palette.notte : Palette.carta)
                )
            }
        }
        .accessibilityHidden(true)
    }
}

/// A full-bleed band of solid colour with a heavy rule on one or both edges: the
/// poster's way of cutting a screen into plates.
struct PosterBand<Content: View>: View {
    enum Edges { case top, bottom, both, none }

    var fill: Color = Palette.carta
    var rule: Color = Palette.inchiostro
    var edges: Edges = .both
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .background(fill)
            .overlay(alignment: .top) {
                if edges == .top || edges == .both { Rectangle().fill(rule).frame(height: 3) }
            }
            .overlay(alignment: .bottom) {
                if edges == .bottom || edges == .both { Rectangle().fill(rule).frame(height: 3) }
            }
    }
}

/// A right-angled triangle with its square corner at the bottom leading edge: the
/// black wedge in the poster's lower left.
struct CornerWedge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
