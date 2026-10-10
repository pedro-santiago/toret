import CoreLocation
import Foundation
import Testing

@testable import Toret

// MARK: - Heading

@Suite("Heading filter")
struct HeadingFilterTests {
    @Test("The first reading sets the dial to its negative")
    func firstReading() {
        var filter = HeadingFilter()
        #expect(filter.update(heading: 90) == -90)
        #expect(filter.smoothed == 90)
    }

    /// The bug this exists to prevent: 359° to 1° as numbers is a 358° swing the
    /// wrong way round.
    @Test("Crossing north turns the dial two degrees, not the long way round")
    func crossingNorth() {
        var filter = HeadingFilter(gain: 1, deadband: 0)
        filter.update(heading: 359)
        let before = filter.dialAngle
        filter.update(heading: 1)
        #expect(abs(filter.dialAngle - before) < 2.5)
    }

    @Test("A full lap accumulates a full turn")
    func fullLap() {
        var filter = HeadingFilter(gain: 1, deadband: 0)
        filter.update(heading: 0)
        for heading in stride(from: 30.0, through: 360, by: 30) {
            filter.update(heading: heading)
        }
        #expect(abs(filter.dialAngle - -360) < 0.001)
    }

    @Test("Jitter inside the deadband does not move the dial")
    func deadband() {
        var filter = HeadingFilter(gain: 1, deadband: 0.6)
        filter.update(heading: 100)
        let still = filter.dialAngle
        filter.update(heading: 100.4)
        filter.update(heading: 99.7)
        #expect(filter.dialAngle == still)
    }

    @Test("The low-pass moves part of the way towards a new reading")
    func smoothing() {
        var filter = HeadingFilter(gain: 0.3, deadband: 0)
        filter.update(heading: 0)
        filter.update(heading: 10)
        #expect(abs((filter.smoothed ?? 0) - 3) < 0.001)
    }

    @Test("Smoothing also takes the short arc across north")
    func smoothingAcrossNorth() throws {
        var filter = HeadingFilter(gain: 0.5, deadband: 0)
        filter.update(heading: 350)
        filter.update(heading: 10)
        let smoothed = try #require(filter.smoothed)
        #expect(Bearing.separation(smoothed, 0) < 0.001)
    }

    @Test("Reset puts the dial back to north-up")
    func reset() {
        var filter = HeadingFilter()
        filter.update(heading: 200)
        filter.reset()
        #expect(filter.dialAngle == 0)
        #expect(filter.smoothed == nil)
    }
}

@Suite("Alignment")
struct AlignmentTrackerTests {
    @Test("It engages inside the threshold, once")
    func engages() {
        var tracker = AlignmentTracker()
        let fired1 = tracker.update(relative: 30)
        #expect(!fired1)
        let fired2 = tracker.update(relative: 6)
        #expect(fired2)
        #expect(tracker.isAligned)
        let fired3 = tracker.update(relative: 3)
        #expect(!fired3)
    }

    /// A single threshold chatters; a one-degree wobble at the edge must not
    /// fire the haptic on and off down the street.
    @Test("Hysteresis: it lets go only outside the wider band")
    func hysteresis() {
        var tracker = AlignmentTracker(enter: 8, exit: 14)
        _ = tracker.update(relative: 5)
        _ = tracker.update(relative: 12)
        #expect(tracker.isAligned)
        _ = tracker.update(relative: 15)
        #expect(!tracker.isAligned)
        let fired4 = tracker.update(relative: 10)
        #expect(!fired4)
        let fired5 = tracker.update(relative: 7)
        #expect(fired5)
    }

    @Test("It reads across the 0/360 seam")
    func seam() {
        var tracker = AlignmentTracker()
        let fired6 = tracker.update(relative: 358)
        #expect(fired6)
        tracker.reset()
        let fired7 = tracker.update(relative: -355)
        #expect(fired7)
    }
}

// MARK: - Bearings and landmarks

@Suite("Compass language")
struct CompassLanguageTests {
    @Test("Winds are spelled out, with the seam on north")
    func cardinals() {
        #expect(Bearing.spokenCardinal(0) == "norte")
        #expect(Bearing.spokenCardinal(44) == "nordeste")
        #expect(Bearing.spokenCardinal(90) == "leste")
        #expect(Bearing.spokenCardinal(225) == "sudoeste")
        #expect(Bearing.spokenCardinal(350) == "norte")
        #expect(Bearing.spokenCardinal(337.4) == "noroeste")
        #expect(Bearing.spokenCardinal(-10) == "norte")
    }

    @Test("Normalising folds any angle into one turn")
    func normalised() {
        #expect(Bearing.normalized(-90) == 270)
        #expect(Bearing.normalized(450) == 90)
        #expect(Bearing.normalized(360) == 0)
    }

    @Test("A fountain is described relative to the way you face")
    func relative() {
        #expect(Bearing.relativePhrase(0) == "à sua frente")
        #expect(Bearing.relativePhrase(90) == "à sua direita")
        #expect(Bearing.relativePhrase(180) == "atrás de você")
        #expect(Bearing.relativePhrase(-90) == "à sua esquerda")
        #expect(Bearing.relativePhrase(315).hasSuffix("à esquerda"))
    }

    /// From the middle of town the Mole and Superga are ten degrees apart; the
    /// two marks must not print over each other.
    @Test("Colliding landmarks step out to the second tier")
    func tiers() {
        let all = Landmark.ring(from: Catalogue.anchor)
        let placed = Landmark.tiers(for: all)
        #expect(placed.count == all.count)
        let inner = placed.filter { $0.tier == .inner }.map(\.landmark.bearing).sorted()
        for pair in zip(inner, inner.dropFirst()) {
            #expect(Bearing.separation(pair.0, pair.1) >= 14)
        }
    }

    @Test("Two landmarks on one bearing end up on different tiers")
    func sameBearing() {
        let marks = Landmark.all(from: CLLocationCoordinate2D(latitude: 45.0690, longitude: 7.6934))
        let placed = Landmark.tiers(for: marks, minimumSeparation: 180)
        #expect(Set(placed.map(\.tier)).count == 2)
    }

    @Test("Facing finds the landmark in front of you, and nothing when there is none")
    func facing() throws {
        let origin = Catalogue.anchor
        let mole = try #require(Landmark.ring(from: origin).first { $0.key == .mole })
        // Exactly on the Mole picks the Mole, even though the Monte dei Cappuccini
        // stands within a few degrees of it from the old town: the nearest wins.
        #expect(Landmark.facing(mole.bearing, from: origin)?.key == .mole)
        #expect(Landmark.facing(mole.bearing + 3, from: origin) != nil)
        let empty = (0 ..< 360).first { Landmark.facing(Double($0), from: origin) == nil }
        #expect(empty != nil)
    }

    @Test("Orientation still answers from outside Turin, measured from the anchor")
    func outsideTurin() {
        let sentence = Landmark.orientation(for: 90, from: Catalogue.anchor)
        #expect(!sentence.isEmpty)
    }
}

// MARK: - Distance

@Suite("Distance figure")
struct DistanceFigureTests {
    @Test("Metres below a kilometre, kilometres from there")
    func units() {
        #expect(DistanceFormat.unit(for: 84) == "m")
        #expect(DistanceFormat.unit(for: 999) == "m")
        #expect(DistanceFormat.unit(for: 1000) == "km")
    }

    @Test("Under ten kilometres keeps one decimal, comma-separated")
    func decimals() {
        #expect(DistanceFormat.figure(84, unit: "m") == "84")
        #expect(DistanceFormat.figure(1240, unit: "km") == "1,2")
        #expect(DistanceFormat.figure(9960, unit: "km") == "10")
        #expect(DistanceFormat.figure(12_400, unit: "km") == "12")
    }

    @Test("A negative figure never prints a minus")
    func negative() {
        #expect(DistanceFormat.figure(-5, unit: "m") == "0")
    }
}

// MARK: - Type

@Suite("Type scale")
@MainActor
struct TypeScaleTests {
    @Test("Poster type never grows past a third")
    func displayCap() {
        let scaled = TypeScale.shared.scale(120, .display)
        #expect(scaled >= 120 && scaled <= 120 * 1.35)
    }

    @Test("Labels scale less than reading text")
    func labelCap() {
        #expect(TypeScale.shared.scale(12, .label) <= 12 * 2.2)
    }
}
