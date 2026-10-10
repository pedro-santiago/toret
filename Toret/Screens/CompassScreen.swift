import SwiftUI

/// The compass, full screen.
///
/// A bearing in degrees is useless to someone who has just come up out of Porta
/// Nuova. So the dial is ringed with things you can actually see from the street
/// — the Duomo, the Mole, Superga, the Alps — and the panel underneath says the
/// bearing as an instruction: *look between the Mole and Superga*. You raise your
/// eyes, find the dome, and start walking. The phone is the last thing you need.
struct CompassScreen: View {
    @Environment(ToretModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var pulse: Double = 0

    var body: some View {
        @Bindable var model = model

        ZStack(alignment: .top) {
            Palette.night.ignoresSafeArea()

            GeometryReader { proxy in
                dial
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.34)
            }

            header

            VStack {
                Spacer()
                panel(compassAlwaysVisible: $model.compassAlwaysVisible)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.linear(duration: 3.6).repeatForever(autoreverses: false)) {
                pulse = 1
            }
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text(model.selectedIsNearest
                ? "BÚSSOLA · FONTE MAIS PRÓXIMA"
                : "BÚSSOLA · FONTE SELECIONADA")
                .font(Typo.narrow(9.5))
                .tracking(Typo.tracking(0.22, at: 9.5))
                .foregroundStyle(Palette.paper.opacity(0.45))

            HStack {
                GlyphButton(diameter: 44, tone: .night, accessibilityText: "Voltar") {
                    Chevron()
                        .stroke(
                            Palette.paper.opacity(0.75),
                            style: .init(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 9, height: 16)
                } action: { dismiss() }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: The dial

    private var dial: some View {
        ZStack {
            Circle().strokeBorder(Palette.sage.opacity(0.14), lineWidth: 1).frame(width: 456, height: 456)
            Circle().strokeBorder(Palette.sage.opacity(0.22), lineWidth: 1).frame(width: 318, height: 318)

            landmarkRing

            TickRing().stroke(Palette.paper.opacity(0.45), lineWidth: 1).frame(width: 260, height: 260)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Palette.sage.opacity(0.13), Palette.sage.opacity(0)],
                        center: .center, startRadius: 0, endRadius: 84
                    )
                )
                .overlay { Circle().strokeBorder(Palette.sage.opacity(0.4), lineWidth: 1.5) }
                .frame(width: 228, height: 228)

            AccuracyRing(progress: pulse, diameter: 228, tint: Palette.sage)

            // A vignette that lets the reading sit clear of the ticks behind it.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Palette.night.opacity(0.9), Palette.night.opacity(0)],
                        center: .center, startRadius: 36, endRadius: 52
                    )
                )
                .frame(width: 140, height: 140)

            Circle().strokeBorder(Palette.sage.opacity(0.2), lineWidth: 1).frame(width: 106, height: 106)

            crosshair
            cardinals

            Needle.dial(angle: model.needleAngle)
                .animation(Motion.needle, value: model.selectionToken)

            reading
        }
        .frame(width: 456, height: 456)
    }

    /// The ring labels, with colliding ones stepped inwards.
    ///
    /// The bearings are real, and from the middle of town the Mole and Superga
    /// are only ten degrees apart. Rather than let two labels overprint, each one
    /// that lands close to the previous is pushed a line further down the radius.
    private var ringLabels: [(landmark: Landmark, inset: CGFloat)] {
        let sorted = model.landmarks.sorted { $0.bearing < $1.bearing }
        var placed: [(Landmark, CGFloat)] = []
        var lastBearing = -1000.0
        var depth = 0
        for mark in sorted {
            depth = Bearing.separation(mark.bearing, lastBearing) < 22 ? depth + 1 : 0
            placed.append((mark, CGFloat(depth) * 21))
            lastBearing = mark.bearing
        }
        return placed.map { (landmark: $0.0, inset: $0.1) }
    }

    private var landmarkRing: some View {
        ZStack {
            ForEach(ringLabels, id: \.landmark.id) { entry in
                ZStack(alignment: .top) {
                    Color.clear
                    VStack(spacing: 8) {
                        Rectangle()
                            .fill(Palette.paper.opacity(0.5))
                            .frame(width: 1, height: 11)
                        Text(entry.landmark.name)
                            .font(Typo.narrow(11))
                            .tracking(Typo.tracking(0.1, at: 11))
                            .foregroundStyle(Palette.paper.opacity(0.85))
                            .fixedSize()
                            .rotationEffect(.degrees(-entry.landmark.bearing))
                            .padding(.top, entry.inset)
                        Spacer(minLength: 0)
                    }
                    .offset(y: -5)
                }
                .frame(width: 318, height: 318)
                .rotationEffect(.degrees(entry.landmark.bearing))
            }
        }
        .accessibilityHidden(true)
    }

    private var crosshair: some View {
        ZStack {
            Rectangle().fill(Palette.sage.opacity(0.14)).frame(width: 200, height: 1)
            Rectangle().fill(Palette.sage.opacity(0.14)).frame(width: 1, height: 200)
        }
    }

    private var cardinals: some View {
        ZStack {
            cardinal("N", opacity: 0.8).offset(y: -108)
            cardinal("L", opacity: 0.62).offset(x: 108)
            cardinal("S", opacity: 0.62).offset(y: 108)
            cardinal("O", opacity: 0.62).offset(x: -108)
        }
        .accessibilityHidden(true)
    }

    private func cardinal(_ letter: String, opacity: Double) -> some View {
        Text(letter)
            .font(Typo.narrow(11))
            .tracking(Typo.tracking(0.16, at: 11))
            .foregroundStyle(Palette.paper.opacity(opacity))
    }

    private var reading: some View {
        VStack(spacing: 9) {
            CountingMetres(
                metres: model.selected.distance,
                token: model.selectionToken,
                size: 70,
                color: Palette.paper,
                tracking: Typo.tracking(-0.02, at: 70)
            )
            Text("METROS DAQUI")
                .font(Typo.narrow(10.5))
                .tracking(Typo.tracking(0.24, at: 10.5))
                .foregroundStyle(Palette.paper.opacity(0.5))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.selected.distance) metros daqui")
    }

    // MARK: Panel

    private func panel(compassAlwaysVisible: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ArcadeCornice(height: 7, stroke: Palette.sage.opacity(0.6), spacing: 3)
                .opacity(0.55)
                .padding(.bottom, 8)

            VStack(spacing: 8) {
                DisplayText(
                    model.selected.place, size: 27, leading: 1.05,
                    color: Palette.paper, alignment: .center
                )
                // The plate number rides with the state here: on a screen with no
                // map, the number is the only way to tell two fountains apart.
                StatusChip(
                    state: model.selected.state,
                    night: true,
                    text: "\(model.selected.plateTitle) · \(model.selected.state.label)",
                    breathes: true
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Palette.paper.opacity(0.12)).frame(height: 1)
            }
            .padding(.bottom, 11)

            Text(model.orientation)
                .font(Typo.ui(13))
                .lineHeight(1.45, font: Typo.uiInterface(13))
                .foregroundStyle(Palette.sage.opacity(0.95))
                .padding(.bottom, 11)

            Text("FONTES POR PERTO")
                .font(Typo.narrow(9.5))
                .tracking(Typo.tracking(0.14, at: 9.5))
                .foregroundStyle(Palette.paper.opacity(0.5))
                .padding(.bottom, 4)

            ForEach(model.nearest3) { fountain in
                FountainRow(
                    fountain: fountain,
                    needleAngle: fountain.bearing,
                    token: model.selectionToken,
                    isSelected: fountain == model.selected,
                    night: true,
                    compact: true
                ) {
                    model.select(fountain)
                }
            }

            Toggle(isOn: compassAlwaysVisible) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bússola sempre visível")
                        .font(Typo.ui(15, 500))
                        .foregroundStyle(Palette.paper)
                    Text(compassAlwaysVisible.wrappedValue
                        ? "Na tela bloqueada e no widget"
                        : "Só dentro do app")
                        .font(Typo.ui(12))
                        .foregroundStyle(Palette.paper.opacity(0.5))
                }
            }
            .tint(Palette.sage)
            .padding(.top, 15)
        }
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .padding(.bottom, 16)
        .glassPane(cornerRadius: 28, tone: .night)
    }
}

/// A back chevron, drawn rather than borrowed.
struct Chevron: Shape {
    var pointsLeft = true

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointsLeft {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        return path
    }
}

/// The fine tick ring between the landmark labels and the dial — 48 marks, one
/// every seven and a half degrees.
struct TickRing: Shape {
    var ticks = 48
    var inner: CGFloat = 118
    var outer: CGFloat = 128

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        for index in 0 ..< ticks {
            let radians = Double(index) / Double(ticks) * 2 * .pi
            let dx = cos(radians), dy = sin(radians)
            path.move(to: CGPoint(x: c.x + inner * dx, y: c.y + inner * dy))
            path.addLine(to: CGPoint(x: c.x + outer * dx, y: c.y + outer * dy))
        }
        return path
    }
}
