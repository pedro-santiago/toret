import SwiftUI

/// The four durations and curves the design uses, named once.
///
/// CSS transitions are per-property, so these stay separate rather than being
/// collapsed into a single `withAnimation` transaction: the distance counts over
/// 720 ms while the needle is still swinging through its 1.1 s arc.
enum Motion {
    /// Counting a distance up or down. Ease-out cubic, matching `1 - (1-k)³`.
    static let count = SwiftUI.Animation.timingCurve(0.33, 1, 0.68, 1, duration: 0.72)
    /// A pin growing into or out of the selected size.
    static let pin = SwiftUI.Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.35)
    /// The needle taking a turn.
    static let needle = SwiftUI.Animation.timingCurve(0.22, 1, 0.36, 1, duration: 1.1)
    /// Panels and chips reacting to a tap.
    static let ui = SwiftUI.Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.35)
}
