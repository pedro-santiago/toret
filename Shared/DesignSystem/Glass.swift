import SwiftUI

/// The three glasses in the design, each tuned to the ground it floats over.
///
/// Liquid Glass does the work — the blur, the refraction, the way an edge picks
/// up and bends what is behind it, and the way two panes merge when they come
/// close. All this adds is the tint, because Turin's glass is warm: it is glazing
/// in a plaster façade, not a neutral pane. The tint goes *into* the material via
/// `Glass.tint` rather than being painted over the top, so the refraction still
/// shows through it.
enum GlassTone {
    /// Plaster. Floats over the map and the light screens.
    case paper
    /// Cast iron. The compass pill, dark against the map.
    case ink
    /// Night. The compass panel, the lock screen, the home widgets.
    case night

    var glass: Glass {
        switch self {
        case .paper: .regular.tint(Color(hex: 0xFFFDF8, opacity: 0.30))
        case .ink: .regular.tint(Palette.ink.opacity(0.62))
        case .night: .regular.tint(Palette.night.opacity(0.34))
        }
    }

    /// The lit edge. Liquid Glass draws its own, but the design's panes carry a
    /// brighter one — this is the specular line along the top of the pane.
    var hairline: Color {
        switch self {
        case .paper: .white.opacity(0.55)
        case .ink: .white.opacity(0.16)
        case .night: .white.opacity(0.18)
        }
    }

    var prefersDarkContent: Bool { self != .paper }
}

extension View {
    /// Puts a pane of Toret glass behind this view.
    ///
    /// `interactive` gives the pane Liquid Glass's press behaviour — it flexes
    /// and the highlight follows the touch — and should be on for anything you
    /// can tap.
    func glassPane<S: Shape>(
        _ shape: S, tone: GlassTone = .paper, interactive: Bool = false
    ) -> some View {
        glassEffect(
            interactive ? tone.glass.interactive() : tone.glass,
            in: shape
        )
        .overlay {
            // A hairline of light along the top edge, which is what separates a
            // pane of glass from a blurred rectangle.
            shape.stroke(
                LinearGradient(
                    colors: [tone.hairline, tone.hairline.opacity(0.15)],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: 1
            )
            .allowsHitTesting(false)
        }
    }

    /// The common case: a rounded rectangle.
    func glassPane(
        cornerRadius: CGFloat, tone: GlassTone = .paper, interactive: Bool = false
    ) -> some View {
        glassPane(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            tone: tone, interactive: interactive
        )
    }

    /// The other common case: a pill.
    func glassCapsule(tone: GlassTone = .paper, interactive: Bool = false) -> some View {
        glassPane(Capsule(), tone: tone, interactive: interactive)
    }
}

/// Groups panes so Liquid Glass can treat them as one body of glass.
///
/// Inside a container, panes that come near each other merge and separate rather
/// than sliding over one another — the search field and its filter chips behave
/// like one piece of glazing with a mullion, not like two stickers.
struct ToretGlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) { content() }
    }
}
