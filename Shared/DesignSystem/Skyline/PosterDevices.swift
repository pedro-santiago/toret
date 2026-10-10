import SwiftUI

// The poster's furniture that needs type or the chequered diamond.

/// A 3 pt rule running out to a short bold word at its trailing end: the poster's
/// "ITALY" at the foot of the sheet. Decoration, so it is hidden from VoiceOver.
struct PosterFooter: View {
    let word: String
    var color: Color = Palette.inchiostro

    init(_ word: String, color: Color = Palette.inchiostro) {
        self.word = word
        self.color = color
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Rectangle().fill(color).frame(height: 3)
            Text(word.uppercased())
                .font(Typo.display(15, 800))
                .tracking(Typo.tracking(0.06, at: 15))
                .foregroundStyle(color)
                .fixedSize()
        }
        .accessibilityHidden(true)
    }
}

/// The black wedge in the poster's lower left corner with the chequered diamond
/// laid over its slope.
struct PosterCornerTriangle: View {
    var size: CGFloat = 160
    var night = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CornerWedge().fill(night ? Palette.carta : Palette.inchiostro)
            DiamondChecker(
                primary: night ? Palette.seccaNotte : Palette.rosso,
                secondary: Palette.salvia,
                stock: night ? Palette.notteChiara : Palette.cartaChiara,
                edge: night ? Palette.notte : Palette.inchiostro
            )
            .frame(width: size * 0.62, height: size * 0.62)
            .offset(x: size * 0.04, y: -size * 0.06)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
