import SwiftUI

/// The compass, full screen: the poster's moon, with a needle on it.
///
/// A bearing in degrees is useless to someone who has just come up out of Porta
/// Nuova. So the disc carries the one figure that answers the question — how far —
/// at 120 pt, the city's landmarks stand on its rim like the skyline on the
/// poster's horizon, and the plate underneath says the bearing as an instruction:
/// *olhe entre a Mole e Superga*. You raise your eyes, find the spire, and start
/// walking. The phone is the last thing you need.
///
/// With a trustworthy heading the whole dial turns with the phone, so the needle
/// points where the fountain really is and the top of the screen is the way you
/// are facing. Without one — the simulator, a denied permission, a magnetometer
/// the bus has disturbed — it stays a chart with north up and says so.
struct CompassScreen: View {
    @Environment(ToretModel.self) private var model
    @Environment(LocationProvider.self) private var location
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Smooths the magnetometer and keeps an unwrapped dial angle.
    @State private var filter = HeadingFilter()
    @State private var alignment = AlignmentTracker()
    @State private var dialAngle: Double = 0
    @State private var isAligned = false

    /// Radius of the moon. 156 pt leaves the rim's landmarks inside a 402 pt screen.
    private static let radius: CGFloat = 156

    private var fountain: Fountain { model.selected }

    /// The dial turns only when the heading is believable *and* the distances are
    /// measured from the user — from the anchor, the bearing to a fountain says
    /// nothing about where this phone is pointing.
    private var followsHeading: Bool {
        location.hasUsableHeading && location.status.isMeasuringFromUser
    }

    private var arrived: Bool {
        location.status.isMeasuringFromUser && fountain.distance < 20
    }

    private var currentHeading: Double? { filter.smoothed ?? location.heading }

    /// The fountain's bearing relative to the way the phone faces.
    private var relativeBearing: Double? {
        guard followsHeading, let heading = currentHeading else { return nil }
        return fountain.bearing - heading
    }

    var body: some View {
        ZStack(alignment: .top) {
            Palette.notte.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                dialArea
                plate
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { refresh() }
        .onChange(of: location.heading) { refresh() }
        .onChange(of: location.headingAccuracy) { refresh() }
        .onChange(of: followsHeading) { refresh() }
        .onChange(of: model.selected.bearing) { refresh() }
        .onChange(of: model.selectedID) { refresh() }
        .haptic(.tick, on: isAligned) { _, now in now }
        .haptic(.arrival, on: arrived) { _, now in now }
        .haptic(.selection, on: model.selectedID)
        .onChange(of: isAligned) { _, now in
            if now {
                AccessibilityNotification.Announcement(String(localized: "Alinhado com a fonte")).post()
            }
        }
    }

    // MARK: Heading

    /// Feeds the filter and turns the dial. Called whenever anything the angle
    /// depends on may have moved.
    private func refresh() {
        guard followsHeading, let raw = location.heading else {
            filter.reset()
            alignment.reset()
            isAligned = false
            // Back to north-up by the short way: the nearest whole turn.
            withAnimation(Motion.heading) { dialAngle = (dialAngle / 360).rounded() * 360 }
            return
        }
        let angle = filter.update(heading: raw)
        withAnimation(Motion.heading) { dialAngle = angle }
        if let relative = relativeBearing {
            alignment.update(relative: relative)
            if alignment.isAligned != isAligned {
                withAnimation(Motion.snap) { isAligned = alignment.isAligned }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text(headerText)
                .font(Typo.ui(16, 700))
                .foregroundStyle(Palette.carta)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 64)

            HStack {
                Button { dismiss() } label: {
                    Chevron()
                        .stroke(
                            Palette.carta,
                            style: .init(lineWidth: 3, lineCap: .square, lineJoin: .miter)
                        )
                        .frame(width: 10, height: 18)
                        .frame(width: 46, height: 46)
                        .overlay { Circle().strokeBorder(Palette.carta, lineWidth: 2.5) }
                        .contentShape(Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Voltar")
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    /// Says which landmark you are facing when you are facing one; otherwise the
    /// name of the screen.
    private var headerText: String {
        if followsHeading, let heading = currentHeading,
           let facing = Landmark.facing(heading, from: model.origin, tolerance: 10) {
            return String(localized: "De frente para \(facing.spoken)")
        }
        return String(localized: "Bússola")
    }

    // MARK: The dial

    private var dialScale: CGFloat { typeSize.isAccessibilitySize ? 0.78 : 1 }

    private var dialArea: some View {
        let side = (Self.radius + 40) * 2
        return VStack(spacing: 2) {
            lubberLine
            CompassDial(
                radius: Self.radius,
                dialAngle: dialAngle,
                needleAngle: model.needleAngle,
                distance: fountain.distance,
                token: model.selectionToken,
                landmarks: Landmark.tiers(for: model.landmarks),
                isAligned: isAligned
            )
            .scaleEffect(dialScale)
            .frame(width: side * dialScale, height: side * dialScale)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Bússola. \(fountain.place)"))
        .accessibilityValue(Text(spokenDirection))
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// The fixed mark at the top of the dial: the way you are facing.
    private var lubberLine: some View {
        Triangle()
            .fill(isAligned ? Palette.carta : Palette.luna)
            .frame(width: 18, height: 14)
            .rotationEffect(.degrees(180))
            .scaleEffect(isAligned ? 1.4 : 1)
            .opacity(followsHeading ? 1 : 0)
            .animation(Motion.snap, value: isAligned)
            .accessibilityHidden(true)
    }

    private var spokenDirection: String {
        let distance = DistanceFormat.spoken(fountain.distance)
        if let relative = relativeBearing {
            return "\(distance), \(Bearing.relativePhrase(relative))"
        }
        return String(localized: "\(distance), para \(Bearing.spokenCardinal(fountain.bearing))")
    }

    // MARK: The plate

    private var plate: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                plateTitle

                HStack(spacing: 10) {
                    StateMark(state: fountain.state, size: 18, night: true)
                    Text(stateLine)
                        .font(Typo.ui(15, 500))
                        .foregroundStyle(Palette.carta)
                }
                .padding(.top, 12)

                Text(arrived ? String(localized: "Você chegou") : model.orientation)
                    .font(Typo.ui(17, 700))
                    .foregroundStyle(Palette.luna)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                ForEach(statusLines, id: \.self) { line in
                    Text(line)
                        .font(Typo.ui(13))
                        .foregroundStyle(Palette.carta.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }

                nearest
                    .padding(.top, 18)

                alwaysVisible
                    .padding(.top, 6)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity)
        .background(Palette.notteChiara.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.carta).frame(height: 3)
        }
    }

    @ViewBuilder
    private var plateTitle: some View {
        let lines = fountain.titleLines.components(separatedBy: "\n")
        if lines.count > 1 {
            PosterTitle(lines[0], lines[1], size: 36, color: Palette.carta, ruleColor: Palette.carta)
        } else {
            PosterTitle(lines[0], size: 36, color: Palette.carta, ruleColor: Palette.carta)
        }
    }

    /// "Água corrente, relato há 2 h" — or, when nobody has said, just that.
    private var stateLine: String {
        guard fountain.state != .unknown, fountain.community.latestDate != nil else {
            return fountain.state.label
        }
        return "\(fountain.state.label), \(fountain.community.provenance.lowercased())"
    }

    /// What the compass cannot be sure of, said once, quietly.
    private var statusLines: [String] {
        var lines: [String] = []
        if let explanation = location.status.explanation { lines.append(explanation) }
        if location.status.isMeasuringFromUser {
            if location.heading == nil {
                lines.append(String(localized: "Sem bússola neste aparelho: mostrando o norte para cima."))
            } else if !location.hasUsableHeading {
                lines.append(String(localized: "Bússola imprecisa. Gire o celular desenhando um oito para calibrar."))
            }
        } else if location.status != .asking {
            lines.append(String(localized: "Mostrando o norte para cima."))
        }
        return lines
    }

    private var nearest: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.nearest3.enumerated()), id: \.element.id) { index, other in
                Button { model.select(other) } label: {
                    HStack(spacing: 14) {
                        StateMark(state: other.state, size: 20, night: true)
                        Text(other.place(distinguishedIn: model.nearest3))
                            .font(Typo.ui(16, other.id == fountain.id ? 700 : 500))
                            .foregroundStyle(Palette.carta)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(DistanceFormat.figure(other.distance, unit: DistanceFormat.unit(for: other.distance)))
                                .font(Typo.display(24, 800))
                            Text(DistanceFormat.unit(for: other.distance))
                                .font(Typo.ui(13, 600))
                        }
                        .foregroundStyle(Palette.carta)
                    }
                    .padding(.vertical, 11)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) {
                    if index > 0 {
                        Rectangle().fill(Palette.carta.opacity(0.22)).frame(height: 1.5)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("\(other.place), \(DistanceFormat.spoken(other.distance))"))
                .accessibilityAddTraits(other.id == fountain.id ? [.isSelected, .isButton] : .isButton)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Palette.carta).frame(height: 3) }
    }

    private var alwaysVisible: some View {
        @Bindable var model = model
        return Toggle(isOn: $model.compassAlwaysVisible) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bússola sempre visível")
                    .font(Typo.ui(15, 600))
                    .foregroundStyle(Palette.carta)
                Text(model.compassAlwaysVisible
                    ? String(localized: "Na tela bloqueada e no widget")
                    : String(localized: "Só dentro do app"))
                    .font(Typo.ui(12.5))
                    .foregroundStyle(Palette.carta.opacity(0.7))
            }
        }
        .tint(Palette.luna)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Palette.carta.opacity(0.22)).frame(height: 1.5) }
    }
}

// MARK: - The moon

/// The moon, its rim, and everything standing on it.
///
/// Three layers with three different relationships to the phone. The disc and the
/// figure never move. The ring — ticks, N, landmarks, needle — turns with the
/// heading. And the needle turns inside the ring on its own spring, because the
/// fountain's bearing changes when you pick another one or walk, not only when you
/// turn.
private struct CompassDial: View {
    let radius: CGFloat
    let dialAngle: Double
    let needleAngle: Double
    let distance: Int
    let token: Int
    let landmarks: [(landmark: Landmark, tier: Landmark.Tier)]
    let isAligned: Bool

    /// Room outside the rim for what stands on it.
    private let reach: CGFloat = 40

    var body: some View {
        let side = (radius + reach) * 2
        ZStack {
            Circle().fill(Palette.luna).frame(width: radius * 2, height: radius * 2)
            // The horizon the landmarks stand on.
            Circle()
                .strokeBorder(Palette.carta.opacity(0.55), lineWidth: 2)
                .frame(width: radius * 2 + 8, height: radius * 2 + 8)

            ZStack {
                DialTicks(long: false).stroke(Palette.inchiostro.opacity(0.7), lineWidth: 1.5)
                DialTicks(long: true).stroke(Palette.inchiostro, lineWidth: 3)

                northMark

                ForEach(landmarks, id: \.landmark.id) { entry in
                    RimMark(landmark: entry.landmark, radius: radius, reach: reach, tier: entry.tier)
                }

                Needle.dial(angle: needleAngle, diameter: radius * 2)
                    .animation(Motion.needle, value: needleAngle)
            }
            .frame(width: side, height: side)
            .rotationEffect(.degrees(dialAngle))

            // The ring around the figure that engages when you are lined up.
            Circle()
                .strokeBorder(Palette.inchiostro, lineWidth: 3)
                .frame(width: radius * 1.12, height: radius * 1.12)
                .opacity(isAligned ? 1 : 0)
                .scaleEffect(isAligned ? 1 : 0.9)
                .animation(Motion.snap, value: isAligned)

            figure
        }
        .frame(width: side, height: side)
    }

    private var figure: some View {
        VStack(spacing: -10) {
            CountingDistance(
                metres: distance, token: token, size: 120,
                width: radius * 1.1, color: Palette.inchiostro
            )
            Text(DistanceFormat.unit(for: distance))
                .font(Typo.ui(22, 700))
                .foregroundStyle(Palette.inchiostro)
        }
        .offset(y: 2)
    }

    /// An N standing on the rim at north, so the chart is legible when it turns.
    private var northMark: some View {
        ZStack(alignment: .top) {
            Color.clear
            Text("N")
                .font(Typo.display(17, 900))
                .foregroundStyle(Palette.carta)
                .offset(y: reach - 24)
        }
        .frame(width: (radius + reach) * 2, height: (radius + reach) * 2)
        .accessibilityHidden(true)
    }
}

/// One landmark, standing upright on the rim at its real bearing.
private struct RimMark: View {
    let landmark: Landmark
    let radius: CGFloat
    let reach: CGFloat
    let tier: Landmark.Tier

    private var size: CGSize {
        switch landmark.glyph {
        case .lozenge: CGSize(width: 20, height: 40)
        case .dome: CGSize(width: 24, height: 20)
        case .square: CGSize(width: 20, height: 15)
        case .range: CGSize(width: 38, height: 20)
        case .arch: CGSize(width: 14, height: 16)
        }
    }

    var body: some View {
        let outward: CGFloat = tier == .outer ? 22 : 0
        let side = (radius + reach) * 2
        ZStack(alignment: .top) {
            Color.clear
            glyph
                .frame(width: size.width, height: size.height)
                // Bottom of the glyph on the horizon, 4 pt clear of the disc.
                .offset(y: reach - 4 - size.height - outward)
        }
        .frame(width: side, height: side)
        .rotationEffect(.degrees(landmark.bearing))
        .accessibilityHidden(true)
    }

    @ViewBuilder private var glyph: some View {
        switch landmark.glyph {
        case .lozenge:
            // The Mole, drawn in cream on the night plate: its spire is the one
            // thing in Turin you can find from anywhere in it.
            MoleSilhouette(
                dome: Palette.salvia, domeShade: Palette.salviaScura,
                stone: Palette.facciata, ink: Palette.carta
            )
        case .dome:
            VStack(spacing: 0) {
                HalfDisc().fill(Palette.salvia)
                Rectangle().fill(Palette.facciata).frame(height: 5)
            }
        case .square:
            Rectangle().fill(Palette.facciata)
                .overlay(alignment: .top) { Rectangle().fill(Palette.rosso).frame(height: 4) }
        case .range:
            MountainRange()
        case .arch:
            ArchGlyph().stroke(Palette.carta, lineWidth: 2)
        }
    }
}

/// Ticks on the moon's rim, every 5°, with a longer one every 30°.
private struct DialTicks: Shape {
    var long: Bool

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        var path = Path()
        for degrees in stride(from: 0, to: 360, by: 5) {
            let isLong = degrees % 30 == 0
            guard isLong == long else { continue }
            let inner = outer * (isLong ? 0.9 : 0.935)
            let radians = (Double(degrees) - 90) * .pi / 180
            let dx = CGFloat(cos(radians)), dy = CGFloat(sin(radians))
            path.move(to: CGPoint(x: centre.x + inner * dx, y: centre.y + inner * dy))
            path.addLine(to: CGPoint(x: centre.x + outer * dx, y: centre.y + outer * dy))
        }
        return path
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
