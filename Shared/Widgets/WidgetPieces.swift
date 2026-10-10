import AppIntents
import SwiftUI
import WidgetKit

// The pieces every widget is cut from. They live in Shared so the app can render
// them too (the unit tests draw each family to a PNG), and so the home-screen
// widget and the Lock Screen one can never drift apart.

/// Black on cream by day; whatever the system asks for when it tints the widget.
struct WidgetInk {
    let mode: WidgetRenderingMode

    var color: Color { mode == .fullColor ? Palette.inchiostro : .primary }
    var secondary: Color { color.opacity(mode == .fullColor ? 0.72 : 0.8) }
}

/// A figure and its unit: 84 → "84" "m".
struct DistanceFigure: View {
    let metres: Int
    var size: CGFloat
    var color: Color = Palette.inchiostro

    var body: some View {
        let parts = DistanceFormat.parts(metres)
        HStack(alignment: .lastTextBaseline, spacing: size * 0.06) {
            Text(parts.value)
                .font(Typo.display(size, 900))
                .tracking(Typo.tracking(-0.01, at: size))
                .foregroundStyle(color)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(parts.unit)
                .font(Typo.ui(max(11, size * 0.26), 700))
                .foregroundStyle(color)
        }
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DistanceFormat.spoken(metres))
    }
}

/// The sun, with a black triangle on its rim at the bearing to the fountain.
///
/// A widget cannot know which way the phone faces, so the dial is a chart: north
/// is up, and the "N" above it says so. The triangle points where the fountain
/// *is*, never "ahead".
struct BearingDisc<Content: View>: View {
    let bearing: Double
    var diameter: CGFloat
    var fill: Color = Palette.sole
    var needle: Color = Palette.inchiostro
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle().fill(fill)
            content()
            Needle(
                angle: bearing, diameter: diameter,
                headWidth: diameter * 0.2, headHeight: diameter * 0.22,
                headInset: diameter * 0.03, tint: needle
            )
            .widgetAccentable()
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// "N", set over a dial: the one word that makes it a chart rather than a promise.
struct NorthLabel: View {
    var color: Color = Palette.inchiostro

    var body: some View {
        Text("N")
            .font(Typo.ui(11, 800))
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

/// The button that steps to the next-nearest fountain: a square, a triangle.
struct CycleButton: View {
    let count: Int
    var ink: Color = Palette.inchiostro

    var body: some View {
        if count > 1 {
            Button(intent: CycleFountainIntent(count: count)) {
                Triangle()
                    .fill(ink)
                    .frame(width: 10, height: 10)
                    .rotationEffect(.degrees(90))
                    .frame(width: 30, height: 30)
                    .overlay { Rectangle().strokeBorder(ink, lineWidth: 2) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Próxima fonte")
        }
    }
}

/// A state mark and the sentence beside it.
struct StateLine: View {
    let fountain: Fountain
    var size: CGFloat = 12
    var ink: Color = Palette.inchiostro

    var body: some View {
        HStack(spacing: 6) {
            StateMark(state: fountain.state, size: size + 4)
            Text(fountain.state.label)
                .font(Typo.ui(size, 600))
                .foregroundStyle(ink.opacity(0.85))
                .lineLimit(1)
        }
    }
}

/// The river at the foot of the plate, edge to edge.
struct WidgetRiver: View {
    var height: CGFloat = 12

    var body: some View {
        WaterStripes(bands: 3, gap: Palette.carta)
            .frame(height: height)
            .frame(maxWidth: .infinity)
    }
}

/// What to say when there is nothing to measure: a diamond, a heading, a line.
struct EmptyReading: View {
    let reading: WidgetReading
    var ink: Color = Palette.inchiostro

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Diamond().stroke(ink, lineWidth: 2.5).frame(width: 26, height: 26)
            Text(reading.savedIsEmpty ? "Nenhuma fonte salva" : "Sem fontes para mostrar")
                .font(Typo.ui(17, 800))
                .foregroundStyle(ink)
            Text(reading.savedIsEmpty
                ? "Salve uma fonte no app e ela aparece aqui."
                : "Não há fonte conhecida perto daqui.")
                .font(Typo.ui(13))
                .foregroundStyle(ink.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension Fountain {
    /// The second line under a name on a widget: where it is, or — when the
    /// distances are measured from the old town — which neighbourhood it is in.
    func widgetDetail(measuredFromUser: Bool, long: Bool = false) -> String {
        guard measuredFromUser else { return zone }
        let walk = long ? "\(walkingMinutes) min a pé" : "\(walkingMinutes) min"
        return "\(cardinalPhrase) · \(walk)"
    }
}
