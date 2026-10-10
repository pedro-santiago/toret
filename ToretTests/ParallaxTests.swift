import CoreGraphics
import Testing
import UIKit

@testable import Toret

// MARK: - Offsets

@Suite("Parallax offsets")
struct ParallaxOffsetTests {
    private let still = CGSize.zero

    @Test("Nothing moves at rest")
    func atRest() {
        for depth in stride(from: 0.0, through: 1.0, by: 0.25) {
            let offset = ParallaxMath.offset(depth: depth, scroll: 0, tilt: still)
            #expect(offset == .zero)
        }
    }

    /// The Mole should stay while the arcades go by: the farther the layer, the more it
    /// lags behind the scrolling header, and a layer at your feet does not lag at all.
    @Test("Distant layers lag the scroll, near ones follow it")
    func scrollLag() {
        let far = ParallaxMath.offset(depth: 0, scroll: 100, tilt: still)
        let middle = ParallaxMath.offset(depth: 0.5, scroll: 100, tilt: still)
        let near = ParallaxMath.offset(depth: 1, scroll: 100, tilt: still)
        #expect(abs(far.height - ParallaxMath.scrollLag * 100) < 0.0001)
        #expect(abs(middle.height - ParallaxMath.scrollLag * 50) < 0.0001)
        #expect(near.height == 0)
        #expect(far.width == 0)
    }

    @Test("The scroll lag stops growing once the header is gone")
    func scrollIsClamped() {
        let capped = ParallaxMath.offset(depth: 0, scroll: ParallaxMath.maximumScroll, tilt: .zero)
        let beyond = ParallaxMath.offset(depth: 0, scroll: ParallaxMath.maximumScroll * 4, tilt: .zero)
        #expect(capped == beyond)
        // Bouncing past the top is not a scroll.
        #expect(ParallaxMath.offset(depth: 0, scroll: -80, tilt: .zero) == .zero)
    }

    @Test("Tilt moves near layers more, against the tip")
    func tiltScalesWithDepth() {
        let right = CGSize(width: 1, height: 0)
        let far = ParallaxMath.offset(depth: 0.1, scroll: 0, tilt: right)
        let middle = ParallaxMath.offset(depth: 0.5, scroll: 0, tilt: right)
        let near = ParallaxMath.offset(depth: 1, scroll: 0, tilt: right)
        #expect(near.width == -ParallaxMath.maximumTilt)
        #expect(abs(middle.width + ParallaxMath.maximumTilt / 2) < 0.0001)
        #expect(abs(far.width) < abs(middle.width) && abs(middle.width) < abs(near.width))
        // Tipping the other way mirrors it.
        let left = ParallaxMath.offset(depth: 1, scroll: 0, tilt: CGSize(width: -1, height: 0))
        #expect(left.width == ParallaxMath.maximumTilt)
    }

    @Test("A tilt past full is held at full")
    func tiltIsClamped() {
        let huge = ParallaxMath.offset(depth: 1, scroll: 0, tilt: CGSize(width: 9, height: -9))
        let full = ParallaxMath.offset(depth: 1, scroll: 0, tilt: CGSize(width: 1, height: -1))
        #expect(huge == full)
        #expect(abs(huge.width) <= ParallaxMath.maximumTilt)
    }

    @Test("A depth outside 0...1 is held to the ends")
    func depthIsClamped() {
        let tilt = CGSize(width: 1, height: 0)
        #expect(ParallaxMath.offset(depth: 7, scroll: 0, tilt: tilt)
            == ParallaxMath.offset(depth: 1, scroll: 0, tilt: tilt))
        #expect(ParallaxMath.offset(depth: -3, scroll: 40, tilt: tilt)
            == ParallaxMath.offset(depth: 0, scroll: 40, tilt: tilt))
    }
}

// MARK: - What may move

@Suite("Parallax allowance")
struct ParallaxAllowanceTests {
    @Test("Reduce Motion stops both the tilt and the scroll lag")
    func reduceMotion() {
        let allowance = ParallaxMath.Allowance.resolve(reduceMotion: true, lowPower: false, hasMotionSensor: true)
        #expect(!allowance.tilt && !allowance.scroll)
        let offset = ParallaxMath.offset(
            depth: 0.5, scroll: 200, tilt: CGSize(width: 1, height: 1), allowance: allowance
        )
        #expect(offset == .zero)
    }

    @Test("Low Power Mode stops the tilt, which costs battery, but not the scroll")
    func lowPower() {
        let allowance = ParallaxMath.Allowance.resolve(reduceMotion: false, lowPower: true, hasMotionSensor: true)
        #expect(!allowance.tilt)
        #expect(allowance.scroll)
    }

    @Test("Without a motion sensor there is no tilt")
    func noSensor() {
        let allowance = ParallaxMath.Allowance.resolve(reduceMotion: false, lowPower: false, hasMotionSensor: false)
        #expect(!allowance.tilt)
        #expect(allowance.scroll)
    }

    @Test("With nothing in the way, both are allowed")
    func everything() {
        let allowance = ParallaxMath.Allowance.resolve(reduceMotion: false, lowPower: false, hasMotionSensor: true)
        #expect(allowance == ParallaxMath.Allowance())
    }
}

// MARK: - The arrival

@Suite("Parallax arrival")
struct ParallaxArrivalTests {
    @Test("Everything starts below the fold and ends home")
    func ends() {
        for depth in stride(from: 0.0, through: 1.0, by: 0.2) {
            #expect(ParallaxMath.entranceOffset(depth: depth, progress: 0) > 0)
            #expect(ParallaxMath.entranceOffset(depth: depth, progress: 1) == 0)
        }
    }

    /// The sun first, the river last: a far layer is on its way while a near one has not
    /// begun to move.
    @Test("Far layers start before near ones")
    func staggered() {
        #expect(ParallaxMath.entranceProgress(depth: 0.06, progress: 0.2) > 0)
        #expect(ParallaxMath.entranceProgress(depth: 0.92, progress: 0.2) == 0)
        let starts = ParallaxLayer.allCases.map { ParallaxMath.entranceDelay(depth: $0.depth) }
        #expect(starts == starts.sorted())
    }

    @Test("A layer only ever moves towards home")
    func monotonic() {
        for layer in ParallaxLayer.allCases {
            var previous = CGFloat.greatestFiniteMagnitude
            for step in 0 ... 20 {
                let offset = ParallaxMath.entranceOffset(depth: layer.depth, progress: CGFloat(step) / 20)
                #expect(offset <= previous + 0.0001)
                previous = offset
            }
        }
    }

    @Test("The ease-out spends its speed first")
    func easeOut() {
        #expect(ParallaxMath.easeOut(0) == 0)
        #expect(ParallaxMath.easeOut(1) == 1)
        #expect(ParallaxMath.easeOut(0.25) > 0.6)
        #expect(ParallaxMath.easeOut(-1) == 0 && ParallaxMath.easeOut(2) == 1)
    }
}

// MARK: - The tilt filter

@Suite("Tilt filter")
struct TiltFilterTests {
    @Test("The first sample is the resting angle, so nothing is tilted")
    func firstSampleIsRest() {
        var filter = TiltFilter()
        #expect(filter.update(CGSize(width: 0.4, height: -0.7)) == .zero)
    }

    @Test("Tipping the phone tilts the scene, smoothly rather than all at once")
    func glides() {
        var filter = TiltFilter()
        _ = filter.update(.zero)
        let first = filter.update(CGSize(width: 0.26, height: 0))
        var last = first
        for _ in 0 ..< 30 { last = filter.update(CGSize(width: 0.26, height: 0)) }
        #expect(first.width > 0 && first.width < 0.5)
        #expect(last.width > first.width)
        #expect(last.width <= 1)
    }

    @Test("A tilt past full is held at full")
    func clamps() {
        var filter = TiltFilter()
        _ = filter.update(.zero)
        var last = CGSize.zero
        for _ in 0 ..< 200 { last = filter.update(CGSize(width: 5, height: -5)) }
        #expect(last.width <= 1 && last.height >= -1)
    }

    /// A phone held at a new angle for a while becomes the new rest: the scene answers a
    /// change of angle, it does not lean for good.
    @Test("A held angle is absorbed into the baseline")
    func recentres() {
        var filter = TiltFilter()
        _ = filter.update(.zero)
        var last = CGSize.zero
        for _ in 0 ..< 900 { last = filter.update(CGSize(width: 0.2, height: 0)) }
        #expect(abs(last.width) < 0.05)
    }

    @Test("Resetting forgets the resting angle")
    func reset() {
        var filter = TiltFilter()
        _ = filter.update(.zero)
        _ = filter.update(CGSize(width: 0.3, height: 0))
        filter.reset()
        #expect(filter.value == .zero)
        #expect(filter.baseline == nil)
        // The next sample is a new resting angle again.
        #expect(filter.update(CGSize(width: 0.9, height: 0.9)) == .zero)
    }
}

// MARK: - The layers

@Suite("Poster scene layers")
@MainActor
struct PosterSceneLayerTests {
    private static let placements: [PosterSceneGeometry.Placement] = [
        PosterSceneGeometry.alps, PosterSceneGeometry.mole, PosterSceneGeometry.city,
        PosterSceneGeometry.corner, PosterSceneGeometry.quay,
    ]

    @Test("Every layer image is in the app")
    func imagesExist() {
        for placement in Self.placements {
            #expect(UIImage(named: placement.image) != nil, "\(placement.image) is missing from the asset catalogue")
        }
    }

    @Test("Layers are listed far to near, so depth never decreases")
    func depthOrder() {
        let depths = ParallaxLayer.allCases.map(\.depth)
        #expect(depths == depths.sorted())
        #expect(depths.allSatisfy { (0 ... 1).contains($0) })
    }

    /// A layer that touches the scene's edge is padded sideways by `layoutInset` so a tilt
    /// can slide it without uncovering the stock; the padding must stay inside that reach.
    @Test("Layers stay within the scene and its sideways padding")
    func placement() {
        let size = PosterSceneGeometry.size
        let reach = ParallaxMath.layoutInset
        for placement in Self.placements {
            let frame = placement.frame
            #expect(frame.width > 0 && frame.height > 0)
            #expect(frame.minX >= -reach - 0.5)
            #expect(frame.maxX <= size.width + reach + 0.5)
            #expect(frame.minY >= 0)
            #expect(frame.maxY <= size.height + 0.5)
        }
    }

    @Test("The sun and the dot fit inside the scene")
    func discs() {
        let size = PosterSceneGeometry.size
        for disc in [PosterSceneGeometry.sun, PosterSceneGeometry.dot] {
            #expect(disc.radii.width > 0 && disc.radii.height > 0)
            #expect(disc.centre.x - disc.radii.width >= 0)
            #expect(disc.centre.x + disc.radii.width <= size.width)
            #expect(disc.centre.y - disc.radii.height >= 0)
        }
        // The poster's sun is a little taller than it is wide.
        #expect(PosterSceneGeometry.sun.radii.height > PosterSceneGeometry.sun.radii.width)
    }

    @Test("The river sits at the foot and its stripes are inside it")
    func river() {
        let river = PosterSceneGeometry.river
        #expect(river.maxY <= PosterSceneGeometry.size.height + 0.5)
        #expect(!PosterSceneGeometry.riverStripes.isEmpty)
        for stripe in PosterSceneGeometry.riverStripes {
            #expect(stripe.y >= 0 && stripe.y + stripe.height <= river.height)
        }
    }
}
