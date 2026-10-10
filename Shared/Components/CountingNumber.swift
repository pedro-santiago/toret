import SwiftUI

/// A number that counts to its new value instead of cutting to it.
///
/// Tap another fountain and the distance runs — 84 to 240 over 720 ms on an
/// ease-out cubic. That run is the whole reason the figure is set in Black at
/// 70 pt: it is a measurement changing, and you should be able to watch it
/// change. `contentTransition(.numericText())` rolls digits; this interpolates
/// the value itself, which is a different, slower, more physical thing.
struct CountingNumber<Content: View>: View, Animatable {
    var value: Double
    @ViewBuilder var content: (Int) -> Content

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        content(Int(value.rounded()))
    }
}

extension View {
    /// Drives a ``CountingNumber`` from a selection token.
    func counts(on token: Int) -> some View {
        animation(Motion.count, value: token)
    }
}

/// A distance in metres, counting, with the unit set separately so the figure
/// keeps the Spartan and the unit keeps the Archivo.
struct CountingMetres: View {
    var metres: Int
    var token: Int
    var size: CGFloat
    var weight: CGFloat = 500
    var color: Color = Palette.ink
    var tracking: CGFloat = 0

    var body: some View {
        CountingNumber(value: Double(metres)) { shown in
            Text(String(shown))
                .font(Typo.display(size, weight))
                .tracking(tracking)
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .animation(Motion.count, value: token)
        .accessibilityLabel("\(metres) metros")
    }
}
