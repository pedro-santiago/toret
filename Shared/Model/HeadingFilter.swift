import Foundation

/// Smooths the device heading and keeps an unwrapped dial angle.
///
/// The magnetometer reports 0..<360 in steps of a few degrees and jitters by a
/// couple either way. Feeding that to an animation makes the dial shiver, and
/// crossing north — 359° to 1° — would spin it the long way round. So the filter
/// does two things: a circular low-pass (an exponential average taken along the
/// *short arc*, never across the 0/360 seam) and an accumulated angle built from
/// signed short deltas, the same trick the needle uses.
struct HeadingFilter: Sendable {
    /// How much of each new reading is believed, 0...1. Lower is calmer and laggier.
    var gain: Double = 0.3
    /// Readings closer than this to the smoothed value are ignored: the shiver.
    var deadband: Double = 0.6

    private(set) var smoothed: Double?
    /// The unwrapped angle the dial should show: `-heading`, accumulated.
    private(set) var dialAngle: Double = 0

    /// Feeds one reading, in degrees clockwise from north. Returns the new dial angle.
    @discardableResult
    mutating func update(heading: Double) -> Double {
        guard let current = smoothed else {
            smoothed = heading
            dialAngle = -heading
            return dialAngle
        }
        let delta = Bearing.shortestDelta(from: current, to: heading)
        guard abs(delta) >= deadband else { return dialAngle }
        let next = Bearing.normalized(current + delta * gain)
        smoothed = next
        dialAngle += Bearing.shortestDelta(from: -current, to: -next)
        return dialAngle
    }

    /// Forgets the heading, for when the compass stops being trusted: the dial
    /// goes back to north-up and the next reading starts fresh.
    mutating func reset() {
        smoothed = nil
        dialAngle = 0
    }
}

/// Decides when the phone is "lined up" with the fountain.
///
/// A single threshold chatters: at exactly 8° off, a one-degree wobble fires the
/// haptic on and off all the way down the street. So it is a Schmitt trigger —
/// it engages inside `enter` and only lets go outside `exit`.
struct AlignmentTracker: Sendable {
    var enter: Double = 8
    var exit: Double = 14
    private(set) var isAligned = false

    /// `relative` is the fountain's bearing minus the heading, in degrees.
    /// Returns `true` only on the update that *becomes* aligned.
    @discardableResult
    mutating func update(relative: Double) -> Bool {
        let off = abs(Bearing.shortestDelta(from: 0, to: relative))
        if isAligned {
            if off > exit { isAligned = false }
            return false
        }
        if off <= enter {
            isAligned = true
            return true
        }
        return false
    }

    mutating func reset() { isAligned = false }
}
