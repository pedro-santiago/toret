import SwiftUI

/// The app icon, drawn rather than painted.
///
/// One composition from the poster's own vocabulary: the sun, a toret standing in
/// front of it with its water falling towards the river, and a single red dot.
/// There is no text and nothing finer than a stripe, so it still reads at 60 px
/// on a home screen. `tools/make-icon.sh` renders the three variants this view
/// defines into the asset catalogue; the PNGs are checked in, and this is the
/// source of truth for them.
struct AppIconArt: View {
    enum Variant: CaseIterable {
        /// Cream stock, yellow sun, black toret, blue river.
        case light
        /// The night plate: the sun becomes the moon.
        case dark
        /// Greys only, on black. iOS recolours it with the user's tint.
        case tinted

        var fileName: String {
            switch self {
            case .light: "icon-1024.png"
            case .dark: "icon-1024-dark.png"
            case .tinted: "icon-1024-tinted.png"
            }
        }
    }

    let variant: Variant

    /// The icon is designed on a 1024 grid and scaled to whatever it is given.
    private static let grid: CGFloat = 1024

    private struct Inks {
        var ground: Color, sun: Color, dot: Color, river: Color, gap: Color
        var figure: FigurePalette
    }

    private var inks: Inks {
        switch variant {
        case .light:
            Inks(
                ground: Palette.carta, sun: Palette.sole, dot: Palette.rosso,
                river: Palette.blu, gap: Palette.carta, figure: .silhouette
            )
        case .dark:
            Inks(
                ground: Palette.notte, sun: Palette.luna, dot: Palette.seccaNotte,
                river: Palette.correnteNotte, gap: Palette.notte,
                figure: FigurePalette(
                    column: Palette.carta, facet: Palette.carta, ink: Palette.carta,
                    horn: Palette.carta, water: Palette.correnteNotte, eye: Palette.notte,
                    bowlInner: Palette.notteChiara, gap: Palette.notte
                )
            )
        case .tinted:
            Inks(
                ground: Color(white: 0.06), sun: Color(white: 0.8), dot: Color(white: 0.95),
                river: Color(white: 0.55), gap: Color(white: 0.06),
                figure: .grey(ink: 1, mid: 0.2, water: 0.55, ground: 0.06)
            )
        }
    }

    var body: some View {
        let inks = inks
        GeometryReader { proxy in
            let k = proxy.size.width / Self.grid
            ZStack(alignment: .topLeading) {
                inks.ground

                Circle().fill(inks.sun)
                    .frame(width: 620 * k, height: 620 * k)
                    .position(x: 575 * k, y: 410 * k)

                Circle().fill(inks.dot)
                    .frame(width: 92 * k, height: 92 * k)
                    .position(x: 850 * k, y: 176 * k)

                // The river: four bands, stripes of ground between them.
                VStack(spacing: 0) {
                    ForEach(0 ..< 4, id: \.self) { index in
                        Rectangle().fill(inks.river)
                        if index < 3 { Rectangle().fill(inks.gap).frame(height: 14 * k) }
                    }
                }
                .frame(width: Self.grid * k, height: 196 * k)
                .position(x: Self.grid * k / 2, y: (Self.grid - 98) * k)

                ToretFigure(kind: .toret, state: .running, palette: inks.figure)
                    .frame(width: 724 * ToretFigure.aspect * k, height: 724 * k)
                    .position(x: (96 + 724 * ToretFigure.aspect / 2) * k, y: (832 - 362) * k)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview("Icon") {
    HStack {
        ForEach(AppIconArt.Variant.allCases, id: \.self) { variant in
            AppIconArt(variant: variant).clipShape(RoundedRectangle(cornerRadius: 56, style: .continuous))
        }
    }
    .padding()
}
