import CoreGraphics

/// The arithmetic of the parallax scene, kept apart from the views so it can be tested.
///
/// A layer has a depth from 0 (the sun, far away) to 1 (the river's edge, at your feet).
/// Two things move it, and both obey depth:
///
/// - **Tilt.** Tip the phone and the near layers slide the most, against the tip, so the
///   scene reads as a diorama behind glass rather than a flat picture sliding about.
/// - **Scroll.** The header scrolls away with the list, but the distant layers lag
///   behind it: the Mole seems to stay while the arcades go by.
enum ParallaxMath {
    /// How far the nearest layer moves at full tilt, in points.
    static let maximumTilt: CGFloat = 14
    /// How far a layer at depth 0 lags behind the scroll, as a share of the scroll.
    static let scrollLag: CGFloat = 0.34
    /// How far, in scene points, the layers' side padding reaches past the poster's edge.
    /// Layers are laid out this far to the right of where they belong and the whole group is
    /// moved back by a render offset: SwiftUI does not draw a view's overflow past the left
    /// edge of its parent's layout, so the padding that covers a tilt has to live in
    /// positive coordinates.
    static let layoutInset: CGFloat = 192
    /// How far a screen wider than the poster may show past its edges: the padding less the
    /// room the tilt needs, which is about 14 points of travel at the scale of a phone.
    static let coverReach: CGFloat = 128
    /// Scrolling beyond this does not move the layers further: past it the header is gone.
    static let maximumScroll: CGFloat = 320

    /// What is allowed to move the layers right now.
    struct Allowance: Equatable, Sendable {
        var tilt = true
        var scroll = true

        static let still = Allowance(tilt: false, scroll: false)

        /// Reduce Motion, Low Power Mode and a missing motion sensor each switch tilt off;
        /// only Reduce Motion also stops the scroll lag, because the lag is a movement the
        /// user's own scrolling causes but the system's setting asks to avoid.
        static func resolve(reduceMotion: Bool, lowPower: Bool, hasMotionSensor: Bool) -> Allowance {
            Allowance(tilt: !reduceMotion && !lowPower && hasMotionSensor, scroll: !reduceMotion)
        }
    }

    /// Where a layer sits, relative to where the poster drew it.
    static func offset(
        depth: CGFloat, scroll: CGFloat, tilt: CGSize, allowance: Allowance = Allowance()
    ) -> CGSize {
        let depth = min(1, max(0, depth))
        var x: CGFloat = 0
        var y: CGFloat = 0
        if allowance.tilt {
            let clamped = clampedTilt(tilt)
            x = -clamped.width * maximumTilt * depth
            y = -clamped.height * maximumTilt * depth
        }
        if allowance.scroll {
            y += scrollLag * (1 - depth) * min(maximumScroll, max(0, scroll))
        }
        return CGSize(width: x, height: y)
    }

    static func clampedTilt(_ tilt: CGSize) -> CGSize {
        CGSize(width: min(1, max(-1, tilt.width)), height: min(1, max(-1, tilt.height)))
    }

    // MARK: Entrance

    /// How far below its place a layer starts when the scene first arrives, in points.
    static let entranceTravel: CGFloat = 220

    /// The share of the arrival, 0...1, that has to pass before a layer starts to move.
    /// Far layers go first: the sun, then the Alps, the Mole, the city and the river.
    static func entranceDelay(depth: CGFloat) -> CGFloat { min(1, max(0, depth)) * 0.42 }

    /// A layer's progress, 0...1, when the whole arrival is `progress` along.
    static func entranceProgress(depth: CGFloat, progress: CGFloat) -> CGFloat {
        let delay = entranceDelay(depth: depth)
        let local = (progress - delay) / (1 - 0.42)
        return min(1, max(0, local))
    }

    /// Strong ease-out: the layer spends its speed at the start, where it is watched.
    static func easeOut(_ t: CGFloat) -> CGFloat {
        let t = min(1, max(0, t))
        return 1 - pow(1 - t, 4)
    }

    /// The vertical offset of a layer during the arrival: below the fold at 0, home at 1.
    static func entranceOffset(depth: CGFloat, progress: CGFloat) -> CGFloat {
        let travel = entranceTravel * (1 + depth * 0.6)
        return (1 - easeOut(entranceProgress(depth: depth, progress: progress))) * travel
    }
}

/// Turns the phone's raw gravity vector into a calm tilt, -1...1 on each axis.
///
/// Two filters in one. A low-pass smooths the sensor's jitter so the layers glide rather
/// than shiver. A slow re-centring takes out whatever the phone has been held at for a few
/// seconds, so the scene settles into the resting angle instead of leaning for good: it
/// answers the *change* of angle, which is what a hand actually does.
struct TiltFilter: Equatable, Sendable {
    /// Share of the gap to the target closed per sample. At 30 Hz, 0.15 is about 200 ms.
    var smoothing: CGFloat = 0.15
    /// Share of the offset the baseline absorbs per sample: a time constant of ~3 s at 30 Hz.
    var recentring: CGFloat = 0.011
    /// Raw gravity change (about 15 degrees) that counts as full tilt.
    var fullTilt: CGFloat = 0.26

    private(set) var baseline: CGSize?
    private(set) var value: CGSize = .zero

    init(smoothing: CGFloat = 0.15, recentring: CGFloat = 0.011, fullTilt: CGFloat = 0.26) {
        self.smoothing = smoothing
        self.recentring = recentring
        self.fullTilt = fullTilt
    }

    /// Feeds one sample of gravity (x, y) and returns the smoothed tilt.
    mutating func update(_ raw: CGSize) -> CGSize {
        guard var base = baseline else {
            // The first sample is the resting angle: nothing is tilted yet.
            baseline = raw
            return value
        }
        base.width += (raw.width - base.width) * recentring
        base.height += (raw.height - base.height) * recentring
        baseline = base

        let target = ParallaxMath.clampedTilt(CGSize(
            width: (raw.width - base.width) / fullTilt,
            height: (raw.height - base.height) / fullTilt
        ))
        value.width += (target.width - value.width) * smoothing
        value.height += (target.height - value.height) * smoothing
        return value
    }

    mutating func reset() {
        baseline = nil
        value = .zero
    }
}
