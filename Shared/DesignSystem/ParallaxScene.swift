import Observation
import SwiftUI

/// The poster's artwork as separate planes, so it can have depth.
///
/// Cut from the reference poster by `tools/art/poster_layers.py` and placed by the numbers
/// that script writes (`PosterSceneGeometry`). The sun and the red dot are drawn, not cut,
/// so they can move on their own, and so is the river, because horizontal stripes only seem
/// to flow when they are broken into dashes.
enum ParallaxLayer: CaseIterable, Identifiable, Sendable {
    case sun, alps, mole, dot, city, corner, quay, river

    var id: Self { self }

    /// 0 is far away, 1 is at your feet. Back to front is also far to near.
    var depth: CGFloat {
        switch self {
        case .sun: 0.06
        case .alps: 0.14
        case .mole: 0.30
        case .dot: 0.38
        case .city: 0.56
        case .corner: 0.82
        case .quay: 0.82
        case .river: 0.92
        }
    }
}

/// How far the enclosing scroll view has been scrolled, written by the scroll view and read
/// only by the scene.
///
/// A class rather than state on the screen: the offset changes every frame of a scroll, and
/// the only thing that should be redrawn for it is the scene, not the list under it.
@MainActor
@Observable
final class ParallaxScroll {
    /// Points scrolled past the top; 0 at rest, never negative.
    var offset: CGFloat = 0
}

extension View {
    /// Reports this scroll view's offset to `model`, for a ``ParallaxScene`` inside it.
    func drivesParallax(_ model: ParallaxScroll) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(0, geometry.contentOffset.y + geometry.contentInsets.top)
        } action: { _, offset in
            model.offset = offset
        }
    }
}

/// The poster scene: sun, Alps, the Mole, the city, the quay and the river, in depth.
///
/// Pass `scroll` when the scene sits at the top of a scroll view, `tilt` from the phone's
/// motion, and `arrival` (0 to 1) to bring it in from below the fold. The scene is as wide as
/// the space it is given and as tall as the poster's own proportions make it.
struct ParallaxScene: View {
    var scroll: ParallaxScroll?
    var tilt: CGSize = .zero
    /// 0: every layer below the fold. 1: every layer home.
    var arrival: CGFloat = 1
    var layers: Set<ParallaxLayer> = Set(ParallaxLayer.allCases)
    /// Whether the river flows. Off in places where nothing else is moving.
    var flowing = true
    /// The part of the poster to show, in scene points; the whole of it by default. A screen
    /// that wants only the Mole, or only the river's edge, shows that window at its own width.
    var window: CGRect?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var onScreen = true

    var body: some View {
        let allowance = ParallaxMath.Allowance(tilt: !reduceMotion, scroll: !reduceMotion)
        let scrolled = scroll?.offset ?? 0
        let moves = flowing && !reduceMotion && onScreen && scenePhase == .active

        let shown = window ?? CGRect(origin: .zero, size: PosterSceneGeometry.size)

        GeometryReader { proxy in
            let scale = proxy.size.width / shown.width
            ZStack(alignment: .topLeading) {
                ForEach(ParallaxLayer.allCases) { layer in
                    if layers.contains(layer) {
                        content(of: layer, scale: scale, flowing: moves)
                            .modifier(ArrivalEffect(depth: layer.depth, progress: arrival))
                            .offset(ParallaxMath.offset(
                                depth: layer.depth, scroll: scrolled, tilt: tilt, allowance: allowance
                            ))
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .offset(x: -(shown.minX + ParallaxMath.layoutInset) * scale, y: -shown.minY * scale)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .aspectRatio(shown.size, contentMode: .fit)
        .clipped()
        .onScrollVisibilityChange(threshold: 0.05) { onScreen = $0 }
        .accessibilityHidden(true)
    }

    // MARK: Layers

    @ViewBuilder
    private func content(of layer: ParallaxLayer, scale: CGFloat, flowing: Bool) -> some View {
        switch layer {
        case .sun: disc(PosterSceneGeometry.sun, ink: Palette.sole, scale: scale)
        case .dot: disc(PosterSceneGeometry.dot, ink: Palette.rosso, scale: scale)
        case .alps: image(PosterSceneGeometry.alps, scale: scale)
        case .mole: image(PosterSceneGeometry.mole, scale: scale)
        case .city: image(PosterSceneGeometry.city, scale: scale)
        case .corner: image(PosterSceneGeometry.corner, scale: scale)
        case .quay: image(PosterSceneGeometry.quay, scale: scale)
        case .river: river(scale: scale, flowing: flowing)
        }
    }

    private func image(_ placement: PosterSceneGeometry.Placement, scale: CGFloat) -> some View {
        let frame = placement.frame
        return Image(placement.image)
            .resizable()
            .interpolation(.high)
            .frame(width: frame.width * scale, height: frame.height * scale)
            .position(x: (frame.midX + ParallaxMath.layoutInset) * scale, y: frame.midY * scale)
    }

    private func disc(_ disc: PosterSceneGeometry.Disc, ink: Color, scale: CGFloat) -> some View {
        Ellipse()
            .fill(ink)
            .frame(width: disc.radii.width * 2 * scale, height: disc.radii.height * 2 * scale)
            .rotationEffect(.radians(disc.angle))
            .position(x: (disc.centre.x + ParallaxMath.layoutInset) * scale, y: disc.centre.y * scale)
    }

    private func river(scale: CGFloat, flowing: Bool) -> some View {
        // Wider than the poster's river by the sideways overscan, so a tilt never shows its edge.
        let frame = PosterSceneGeometry.river
        let overscan = 64 * scale
        return RiverView(flowing: flowing, scale: scale)
            .frame(width: frame.width * scale + overscan, height: frame.height * scale)
            .position(
                x: (frame.minX + ParallaxMath.layoutInset) * scale + (frame.width * scale + overscan) / 2,
                y: frame.midY * scale
            )
    }
}

/// Brings a layer in from below the fold, far layers first.
///
/// `Animatable` so that one animation of `progress` drives every layer's own staggered
/// curve: the stagger is arithmetic on the shared value, not a chain of delayed animations.
private struct ArrivalEffect: ViewModifier, Animatable {
    var depth: CGFloat
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.offset(y: ParallaxMath.entranceOffset(depth: depth, progress: progress))
    }
}

/// The river: the poster's blue band with its cream stripes, broken into dashes that slide.
///
/// At rest the dashes nearly meet, which is the poster's unbroken line. Moving, alternate
/// stripes run in opposite directions at about 12 points a second: a current, not a conveyor.
private struct RiverView: View {
    let flowing: Bool
    let scale: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !flowing)) { timeline in
            let seconds = flowing ? timeline.date.timeIntervalSinceReferenceDate : 0
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.blu))
                let dash = 230 * scale
                let gap = 16 * scale
                let period = dash + gap
                for (index, stripe) in PosterSceneGeometry.riverStripes.enumerated() {
                    let y = stripe.y * scale
                    let thickness = max(1.5, stripe.height * scale)
                    let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
                    let shift = CGFloat((seconds * 12).truncatingRemainder(dividingBy: Double(period / scale))) * scale * direction
                    var x = -period + shift.truncatingRemainder(dividingBy: period) + (index % 2 == 0 ? 0 : period / 2)
                    while x < size.width {
                        context.fill(
                            Path(CGRect(x: x, y: y, width: dash, height: thickness)),
                            with: .color(Palette.carta)
                        )
                        x += period
                    }
                }
            }
        }
    }
}

#Preview("Poster scene") {
    ParallaxScene(scroll: nil, tilt: .zero)
        .frame(width: 390)
        .background(Palette.carta)
}
