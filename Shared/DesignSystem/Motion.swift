import SwiftUI
import UIKit

/// Every duration, curve and spring the app uses, named once.
///
/// A printed thing does not glow or fade; it slides, snaps into place and stops.
/// So the tokens are of two kinds, and a call site picks by *what is moving*:
///
/// - **Springs** are for things with weight that the user can disturb: the needle,
///   the pins, the sun on the tab bar. A spring retargets from wherever the value
///   is, carrying its velocity, so grabbing or re-selecting mid-flight never jumps.
/// - **Curves** are for the interface answering a tap: a panel, a chip, a count.
///   Always ease-out — it spends its speed at the start, where the person is
///   watching — and never longer than 350 ms.
///
/// Reduce Motion is honoured here rather than at each call site: with it on, every
/// token becomes a short plain fade-length ease (or a cut, for counts), so no view
/// has to remember. Views that move things by hand (a parallax, a looping stripe)
/// still read `\.accessibilityReduceMotion` themselves; ``isReduced`` is for code
/// that has no environment.
@MainActor
enum Motion {
    /// Whether the user asked the system for less movement.
    static var isReduced: Bool { UIAccessibility.isReduceMotionEnabled }

    /// A short ease-out used in place of any spring or travel when Reduce Motion is
    /// on. Opacity and colour changes still read; position changes just arrive.
    private static let reduced = SwiftUI.Animation.easeOut(duration: 0.16)

    // MARK: Curves — the interface answering a tap

    /// Panels, chips and rows reacting to a tap. Strong ease-out, 280 ms.
    static var ui: SwiftUI.Animation {
        isReduced ? reduced : .timingCurve(0.23, 1, 0.32, 1, duration: 0.28)
    }

    /// A distance counting up or down. Ease-out cubic, 720 ms — long on purpose:
    /// it is a measurement changing and the point is to watch it. Cut when reduced.
    static var count: SwiftUI.Animation {
        isReduced ? .linear(duration: 0.01) : .timingCurve(0.33, 1, 0.68, 1, duration: 0.72)
    }

    /// A screen's worth of content arriving, once, on first appearance. 450 ms.
    static var reveal: SwiftUI.Animation {
        isReduced ? reduced : .timingCurve(0.23, 1, 0.32, 1, duration: 0.45)
    }

    // MARK: Springs — things with weight

    /// The needle taking a turn. Slightly under-damped: it overshoots a few degrees
    /// and settles, the way a real needle does, and a second selection mid-swing
    /// simply redirects it.
    static var needle: SwiftUI.Animation {
        isReduced ? reduced : .spring(response: 0.7, dampingFraction: 0.78)
    }

    /// The dial turning with the phone. Critically damped and quick: it has to
    /// track a hand, not perform. Retargets every heading update without a seam.
    static var heading: SwiftUI.Animation {
        isReduced ? reduced : .smooth(duration: 0.28)
    }

    /// A pin growing into the selected size, or popping onto the map. A little
    /// overshoot — it lands, it does not fade in.
    static var pin: SwiftUI.Animation {
        isReduced ? reduced : .spring(response: 0.38, dampingFraction: 0.7)
    }

    /// The sun sliding to another tab. Settled, with a trace of bounce.
    static var sun: SwiftUI.Animation {
        isReduced ? reduced : .spring(response: 0.45, dampingFraction: 0.82)
    }

    /// The lined-up marker engaging. Quick and decisive.
    static var snap: SwiftUI.Animation {
        isReduced ? reduced : .spring(response: 0.28, dampingFraction: 0.62)
    }

    // MARK: Staggers

    /// The delay for the `index`th item of a list entering, 30 ms apart and capped
    /// at ten so a long list does not take a second to arrive.
    static func stagger(_ index: Int) -> SwiftUI.Animation {
        reveal.delay(isReduced ? 0 : Double(min(index, 10)) * 0.03)
    }
}
