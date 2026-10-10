import SwiftUI

/// The three grounds a plate can be printed on.
///
/// The first version of the app floated panes of Liquid Glass over the map. The
/// poster has no glass: it is flat ink on stock, so a "pane" is now a plate — an
/// opaque rectangle with a black frame, laid over whatever is behind it. The
/// names `glassPane` and `glassCapsule` stay so every call site keeps compiling
/// while the screens are redrawn; neither blurs, tints or rounds anything.
enum GlassTone {
    /// Cream stock. Floats over the map and the light screens.
    case paper
    /// Black ink: the compass pill, a reversed plate.
    case ink
    /// Night: the compass screen's panels.
    case night

    var fill: Color {
        switch self {
        case .paper: Palette.carta
        case .ink: Palette.inchiostro
        case .night: Palette.notteChiara
        }
    }

    var frame: Color {
        switch self {
        case .paper: Palette.inchiostro
        case .ink: Palette.inchiostro
        case .night: Palette.carta.opacity(0.85)
        }
    }

    var prefersDarkContent: Bool { self != .paper }
}

extension View {
    /// Puts a printed plate behind this view.
    ///
    /// `interactive` makes it dip by a couple of points when pressed — the
    /// misregistration of a hand-pulled print — rather than glow.
    func glassPane<S: InsettableShape>(
        _ shape: S, tone: GlassTone = .paper, interactive: Bool = false
    ) -> some View {
        modifier(PlateModifier(shape: shape, tone: tone, interactive: interactive))
    }

    /// The common case: a rectangle. The radius is ignored; the poster has none.
    func glassPane(
        cornerRadius: CGFloat, tone: GlassTone = .paper, interactive: Bool = false
    ) -> some View {
        glassPane(Rectangle(), tone: tone, interactive: interactive)
    }

    /// Formerly a pill. Now a flat rectangle, like everything else that is not a circle.
    func glassCapsule(tone: GlassTone = .paper, interactive: Bool = false) -> some View {
        glassPane(Rectangle(), tone: tone, interactive: interactive)
    }
}

private struct PlateModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let tone: GlassTone
    let interactive: Bool

    func body(content: Content) -> some View {
        content
            .background(shape.fill(tone.fill))
            .overlay { shape.strokeBorder(tone.frame, lineWidth: 2.5) }
            .contentShape(shape)
    }
}

/// Formerly grouped panes of glass so they could merge. Plates do not merge; this
/// is a plain container now, kept so the map screen compiles until it is redrawn.
struct ToretGlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View { content() }
}
