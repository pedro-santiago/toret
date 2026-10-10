import SwiftUI

// MARK: - Landmarks

/// The things you can raise your eyes to and find.
///
/// Each is drawn as its own silhouette rather than as a generic pin: the Mole is
/// a lozenge, Porta Nuova a square, the Monte dei Cappuccini a dome, the Porte
/// Palatine an arch. The point of putting them on the map at all is that they are
/// the marks you can also see over the rooftops — the map and the skyline use the
/// same four shapes, so one confirms the other.
struct LandmarkMarker: View {
    let landmark: Landmark

    var body: some View {
        VStack(spacing: 3) {
            silhouette
                .frame(width: 13, height: landmark.glyph == .arch ? 9 : 13)
            Text(landmark.name)
                .font(Typo.narrow(9.5))
                .tracking(Typo.tracking(0.08, at: 9.5))
                .foregroundStyle(Palette.ink.opacity(0.8))
                .fixedSize()
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background {
                    // A plaster ground so the lettering survives whatever MapKit
                    // has drawn underneath it.
                    Capsule().fill(Palette.paper.opacity(0.82))
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(landmark.name)
    }

    @ViewBuilder private var silhouette: some View {
        Group {
            switch landmark.glyph {
            case .lozenge:
                Rectangle()
                    .strokeBorder(Palette.ink, lineWidth: 1.5)
                    .rotationEffect(.degrees(45))
                    .padding(1.5)
            case .square:
                Rectangle().strokeBorder(Palette.ink, lineWidth: 1.5)
            case .dome:
                Circle().strokeBorder(Palette.ink, lineWidth: 1.5)
            case .arch, .range:
                ArchGlyph().stroke(Palette.ink, lineWidth: 1.5)
            }
        }
        .background {
            Circle().fill(Palette.paper.opacity(0.7)).blur(radius: 3)
        }
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

/// One fountain on the map.
///
/// The colour is the water state and nothing else. The selected pin grows rather
/// than changing colour or gaining a ring, so the two channels never collide.
struct FountainPin: View {
    let fountain: Fountain
    let isSelected: Bool
    var isDimmed: Bool = false
    let token: Int
    let action: () -> Void

    private var diameter: CGFloat { isSelected ? 26 : 18 }
    private var eye: CGFloat { isSelected ? 9 : 6 }

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(fountain.state.color)
                .overlay {
                    Circle()
                        .fill(Palette.paperRaised)
                        .frame(width: eye, height: eye)
                }
                .overlay { Circle().strokeBorder(Palette.paperRaised, lineWidth: 2.5) }
                .frame(width: diameter, height: diameter)
                .shadow(color: Palette.ink.opacity(0.3), radius: 3.5, y: 2)
                .padding(9)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isDimmed ? 0.55 : 1)
        .animation(Motion.pin, value: token)
        .animation(Motion.ui, value: isDimmed)
        .accessibilityLabel("\(fountain.place), \(fountain.plateTitle)")
        .accessibilityValue("\(fountain.state.label), \(fountain.distance) metros")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
