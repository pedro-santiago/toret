import SwiftUI

// MARK: - Landmarks

/// The things you can raise your eyes to and find, printed on the map.
///
/// Each is a flat mark in black ink — the Mole is its own silhouette, the others a
/// diamond, a square, a dome, an arch, a peak — so the map and the skyline use the
/// same few shapes and one confirms the other. They sit under the fountains and
/// say less: a name in a plate, no more.
struct LandmarkMarker: View {
    let landmark: Landmark

    var body: some View {
        VStack(spacing: 3) {
            silhouette
            Text(landmark.name)
                .font(Typo.narrow(10, 700))
                .tracking(Typo.tracking(0.06, at: 10))
                .foregroundStyle(Palette.inchiostro)
                .fixedSize()
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Palette.carta.opacity(0.88))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(landmark.name.capitalized)
    }

    /// The building itself, small: tall things taller, the Alps low and wide.
    private var silhouette: some View {
        let drawn = landmark.drawn
        let height: CGFloat = switch drawn {
        case .mole: 40
        case .alps: 18
        default: 26
        }
        return drawn.view(night: false)
            .frame(width: height * drawn.aspect, height: height)
    }
}

/// A round-headed arch, open at the foot — the Porte Palatine.
struct ArchGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = rect.width / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(180), endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

// MARK: - Accuracy

/// The ring that goes out from a fix once every three and a half seconds.
struct AccuracyRing: View, Animatable {
    var progress: Double
    var diameter: CGFloat
    var tint: Color

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Circle()
            .strokeBorder(tint.opacity(0.45 * max(0, 1 - progress / 0.7)), lineWidth: 1.5)
            .frame(width: diameter, height: diameter)
            .scaleEffect(0.5 + 0.5 * progress)
    }
}

// MARK: - Pins

/// One fountain on the map: its state mark, and nothing else.
///
/// The shape is the water (circle, half-disc, triangle, empty ring) so the map
/// reads without colour. The selected pin *grows* and takes a halo of stock and a
/// black ring rather than changing ink, so the two channels never collide: size
/// says "this one", shape says "what the water is doing".
struct FountainPin: View {
    let fountain: Fountain
    let isSelected: Bool
    var isDimmed: Bool = false
    var density: PinDensity = .full
    let token: Int
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var markSize: CGFloat { isSelected ? 30 : density.markSize }

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    // The halo separates the mark from whatever the basemap has
                    // drawn under it; the ring is the registration mark.
                    Circle().fill(Palette.carta).frame(width: markSize + 14, height: markSize + 14)
                    Circle().strokeBorder(Palette.inchiostro, lineWidth: 3)
                        .frame(width: markSize + 14, height: markSize + 14)
                }
                if density == .dot, !isSelected {
                    dot
                } else {
                    StateMark(state: fountain.state, size: markSize, outlined: true)
                        .background {
                            // Marks that are mostly outline need a ground, or the
                            // street lines show through the ring.
                            if fountain.state == .unknown {
                                Circle().fill(Palette.carta.opacity(0.9)).padding(1.5)
                            }
                        }
                }
            }
            .frame(width: max(density.hitSize, markSize + 14), height: max(density.hitSize, markSize + 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isDimmed ? 0.4 : 1)
        .animation(reduceMotion ? nil : .spring(duration: 0.38, bounce: 0.34), value: isSelected)
        .animation(reduceMotion ? nil : Motion.ui, value: isDimmed)
        .animation(reduceMotion ? nil : Motion.ui, value: density)
        .accessibilityLabel("\(fountain.place), \(fountain.plateTitle)")
        .accessibilityValue(String(localized: "\(fountain.state.label), a \(DistanceFormat.spoken(fountain.distance))"))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// The zoomed-out mark: a solid dot in the state's ink; unknown is a quiet
    /// grey-black one, since an empty ring this small is only mush.
    private var dot: some View {
        Circle()
            .fill(fountain.state == .unknown ? Palette.inchiostro.opacity(0.55) : fountain.state.color)
            .overlay { Circle().strokeBorder(Palette.carta, lineWidth: 1.5) }
            .frame(width: density.markSize, height: density.markSize)
    }
}

/// Neighbours folded together at city zoom: a black disc with the count in it.
struct ClusterBadge: View {
    let cluster: PinCluster
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Wider for more digits, so the count never crowds the ring.
    private var diameter: CGFloat {
        switch cluster.count {
        case ..<10: 32
        case ..<100: 40
        default: 48
        }
    }

    var body: some View {
        Button(action: action) {
            Text("\(cluster.count)")
                .font(Typo.display(15, 800))
                .foregroundStyle(Palette.carta)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(Palette.inchiostro))
                .overlay { Circle().strokeBorder(Palette.carta, lineWidth: 2.5) }
                .frame(width: max(44, diameter), height: max(44, diameter))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
        .accessibilityLabel("\(cluster.count) fontes")
        .accessibilityHint("Aproxima o mapa")
    }
}

// MARK: - Controls

/// The compass, as a small black disc with the needle in it. Tapping opens the
/// compass full screen.
struct MapCompassButton: View {
    let fountain: Fountain
    let needleAngle: Double
    let token: Int
    var isNearest = true
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Needle(
                angle: needleAngle, diameter: 34, headWidth: 11, headHeight: 13, headInset: 3,
                tint: Palette.carta, stemLength: 9, stemColor: Palette.carta.opacity(0.55)
            )
            .animation(reduceMotion ? nil : Motion.needle, value: token)
            .frame(width: 56, height: 56)
            .background(Circle().fill(Palette.inchiostro))
            .overlay { Circle().strokeBorder(Palette.carta, lineWidth: 2.5) }
            .frame(width: 60, height: 60)
            .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(
            isNearest
                ? String(localized: "Bússola. Fonte mais próxima, \(fountain.place), a \(DistanceFormat.spoken(fountain.distance))")
                : String(localized: "Bússola. Fonte selecionada, \(fountain.place), a \(DistanceFormat.spoken(fountain.distance))")
        )
        .accessibilityHint("Abre a bússola em tela cheia")
    }
}

/// A round plate button with a drawn glyph: recentre, and the like.
struct MapRoundButton<Glyph: View>: View {
    let label: String
    @ViewBuilder let glyph: () -> Glyph
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            glyph()
                .frame(width: 48, height: 48)
                .background(Circle().fill(Palette.carta))
                .overlay { Circle().strokeBorder(Palette.inchiostro, lineWidth: 2.5) }
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }
}

/// A target: a ring, a dot, four ticks. "Take me back to where I am."
struct TargetGlyph: View {
    var tint: Color = Palette.inchiostro

    var body: some View {
        ZStack {
            Circle().strokeBorder(tint, lineWidth: 2.2).frame(width: 18, height: 18)
            Circle().fill(tint).frame(width: 6, height: 6)
            ForEach(0 ..< 4, id: \.self) { index in
                Rectangle().fill(tint).frame(width: 2.2, height: 6)
                    .offset(y: -12)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
        }
        .frame(width: 28, height: 28)
    }
}

/// The poster's button: a full-width black block with a yellow disc at the end.
///
/// The arrow is a black triangle on the disc, the same needle head the compass
/// uses. `tone` swaps the block to rosso for the actions that deserve attention
/// (ending a walk, reporting a problem).
struct PosterActionButton: View {
    enum Tone { case ink, rosso }

    let title: String
    var tone: Tone = .ink
    var height: CGFloat = 56
    var showsDisc = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(Typo.display(20, 800))
                    .foregroundStyle(Palette.carta)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                if showsDisc {
                    ZStack {
                        Circle().fill(Palette.sole)
                        Triangle().fill(Palette.inchiostro)
                            .frame(width: 11, height: 12)
                            .rotationEffect(.degrees(90))
                            .offset(x: 1)
                    }
                    .frame(width: 30, height: 30)
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 13)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(tone == .ink ? Palette.inchiostro : Palette.rosso)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }
}

/// The outlined counterpart: a black frame, no fill.
struct PosterOutlineButton: View {
    let title: String
    var height: CGFloat = 52
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typo.display(18, 800))
                .foregroundStyle(Palette.inchiostro)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: height)
                .overlay { Rectangle().strokeBorder(Palette.inchiostro, lineWidth: 2.5) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }
}
