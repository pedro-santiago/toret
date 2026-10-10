import ActivityKit
import CoreLocation
import Foundation

/// The walk to a fountain, as the Lock Screen and the Dynamic Island show it.
///
/// Static facts live here; everything that changes while you walk is
/// ``ContentState``. Both are tiny on purpose — a Live Activity is limited to a
/// few kilobytes and is re-encoded on every update.
struct WalkActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        /// Metres left on the walk.
        var remaining: Int
        /// Metres to the next instruction.
        var toNextTurn: Int
        /// "Vire à direita na Via Po".
        var instruction: String
        var minutes: Int
        /// Bearing from the walker to the fountain, clockwise from north.
        var bearing: Double
        /// Which way the phone faces, when it is known and trustworthy.
        var heading: Double?
        var arrived: Bool

        /// Whether the needle turns with the phone. If not, it points on a
        /// north-up chart and the view labels it as such.
        var isRelative: Bool { heading != nil }

        /// Degrees to rotate a needle that points up when the fountain is dead
        /// ahead.
        var needleAngle: Double {
            guard let heading else { return bearing }
            return (bearing - heading).truncatingRemainder(dividingBy: 360)
        }
    }

    let fountainID: String
    let fountainName: String
    let zone: String
}

/// The arithmetic of a walk, kept apart from the framework that displays it.
enum WalkProgress {
    /// Close enough to call it arrived: a fountain is a metre wide, and a phone's
    /// fix is good to ten.
    static let arrivalRadius: Double = 20
    /// A fix worse than this says nothing about whether you are at the fountain.
    static let trustworthyAccuracy: Double = 50

    static func hasArrived(straightLine: Double, accuracy: Double?) -> Bool {
        if let accuracy, accuracy < 0 || accuracy > trustworthyAccuracy { return false }
        return straightLine <= arrivalRadius
    }

    /// Metres left. The route's own figure is the better one, but it was worked
    /// out where the walker *was*; between recalculations it is brought forward
    /// by how far they have moved since, never below the straight line, which is
    /// the shortest the walk can possibly be.
    static func remaining(
        routeRemaining: Int?, walkedSinceRoute: Double, straightLine: Double
    ) -> Int {
        let floor = Int(straightLine.rounded())
        guard let routeRemaining else { return floor }
        return max(floor, routeRemaining - Int(walkedSinceRoute.rounded()))
    }

    static func minutes(forRemaining metres: Int) -> Int {
        max(1, Int((Double(metres) / 80).rounded()))
    }

    /// Whether an update is worth spending: the system budgets them, and a
    /// needle that jitters by two degrees is not news.
    static func isWorthPublishing(
        previous: WalkActivityAttributes.ContentState?,
        next: WalkActivityAttributes.ContentState,
        lastUpdate: Date?,
        now: Date = .now
    ) -> Bool {
        guard let previous else { return true }
        if next.arrived != previous.arrived { return true }
        if next == previous { return false }
        if let lastUpdate, now.timeIntervalSince(lastUpdate) < 2 { return false }
        if next.instruction != previous.instruction { return true }
        if abs(next.remaining - previous.remaining) >= 5 { return true }
        if (next.heading == nil) != (previous.heading == nil) { return true }
        return Bearing.separation(next.needleAngle, previous.needleAngle) >= 12
    }
}
