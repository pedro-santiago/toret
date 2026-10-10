import CoreMotion
import SwiftUI
import UIKit

/// How the phone is tilted, for the poster scene's parallax.
///
/// Motion updates run at 30 Hz, and only while a scene is on screen: every scene asks with
/// ``retain()`` when it appears and gives it back with ``release()`` when it goes, and the
/// sensor sleeps at zero. Nothing is asked of the user — gravity needs no permission.
///
/// It stays at rest, with `tilt` at zero, when the system asks for less motion (Reduce
/// Motion), when Low Power Mode is on, and where there is no sensor to read, which is the
/// simulator. In a debug build `-toret-tilt 0.8,-0.5` pins a tilt, so a screenshot can show
/// the layers moved without a phone to tip.
@MainActor
@Observable
final class TiltProvider {
    static let shared = TiltProvider()

    /// -1...1 on each axis, smoothed. Positive x is the phone tipped to the right.
    private(set) var tilt: CGSize = .zero

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var filter = TiltFilter()
    @ObservationIgnored private var clients = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        #if DEBUG
        if let pinned = Self.pinnedTilt { tilt = pinned }
        #endif
    }

    func retain() {
        clients += 1
        guard clients == 1 else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.reconcile() } },
            center.addObserver(
                forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.reconcile() } },
        ]
        reconcile()
    }

    func release() {
        clients = max(0, clients - 1)
        guard clients == 0 else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        stop()
    }

    // MARK: Sensor

    private var allowed: Bool {
        ParallaxMath.Allowance.resolve(
            reduceMotion: UIAccessibility.isReduceMotionEnabled,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            hasMotionSensor: manager.isDeviceMotionAvailable
        ).tilt
    }

    private func reconcile() {
        #if DEBUG
        if Self.pinnedTilt != nil { return }
        #endif
        if clients > 0, allowed { start() } else { stop() }
    }

    private func start() {
        guard !manager.isDeviceMotionActive else { return }
        filter.reset()
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let gravity = motion?.gravity else { return }
            let sample = CGSize(width: gravity.x, height: gravity.y)
            MainActor.assumeIsolated { self?.receive(sample) }
        }
    }

    private func stop() {
        if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
        filter.reset()
        tilt = .zero
    }

    private func receive(_ gravity: CGSize) {
        tilt = filter.update(gravity)
    }

    #if DEBUG
    private static let pinnedTilt: CGSize? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-toret-tilt"), arguments.indices.contains(flag + 1) else {
            return nil
        }
        let parts = arguments[flag + 1].split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return ParallaxMath.clampedTilt(CGSize(width: parts[0], height: parts[1]))
    }()
    #endif
}

/// A ``ParallaxScene`` that follows the phone's tilt.
///
/// Reads the provider here, in its own body, rather than at the screen: the tilt changes 30
/// times a second, and only the scene should be redrawn for it.
struct TiltedParallaxScene: View {
    var scroll: ParallaxScroll?
    var arrival: CGFloat = 1
    var layers: Set<ParallaxLayer> = Set(ParallaxLayer.allCases)
    var flowing = true
    var window: CGRect?

    private let provider = TiltProvider.shared

    var body: some View {
        ParallaxScene(
            scroll: scroll, tilt: provider.tilt, arrival: arrival, layers: layers,
            flowing: flowing, window: window
        )
        .onAppear { provider.retain() }
        .onDisappear { provider.release() }
    }
}
