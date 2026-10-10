import CoreLocation
import Foundation

/// One fix, asked for once, from a process that cannot keep a location manager
/// running: a widget refreshing its timeline, or Siri answering a question.
///
/// It never prompts. A widget has no way to show a permission dialog and a spoken
/// answer should not open one; if the user has not already said yes in the app,
/// the result says so and the caller falls back to the old town, labelled.
@MainActor
final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    enum Context: Sendable {
        case app
        case widget
    }

    struct Result: Sendable {
        let fix: MeasuredFix?
        /// The user said no (or the device forbids it), as opposed to "not yet".
        let denied: Bool
    }

    /// A fix this young is used as it is rather than asking the chip for another.
    private static let cachedFor: TimeInterval = 120

    private let manager = CLLocationManager()
    private let context: Context
    private var continuation: CheckedContinuation<Result, Never>?

    private init(context: Context) {
        self.context = context
        super.init()
    }

    static func fetch(
        for context: Context, timeout: Duration = .seconds(6)
    ) async -> Result {
        let fetcher = OneShotLocation(context: context)
        return await fetcher.run(timeout: timeout)
    }

    private func run(timeout: Duration) async -> Result {
        let status = manager.authorizationStatus
        let denied = status == .denied || status == .restricted
        let authorised: Bool
        switch context {
        case .widget: authorised = manager.isAuthorizedForWidgetUpdates
        case .app: authorised = status == .authorizedWhenInUse || status == .authorizedAlways
        }
        guard authorised else { return Result(fix: nil, denied: denied) }

        if let cached = manager.location, usable(cached),
           Date.now.timeIntervalSince(cached.timestamp) <= Self.cachedFor {
            return Result(fix: measured(cached), denied: false)
        }

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finish(with: nil)
            }
        }
    }

    private func usable(_ location: CLLocation) -> Bool { location.horizontalAccuracy >= 0 }

    private func measured(_ location: CLLocation) -> MeasuredFix {
        MeasuredFix(
            coordinate: location.coordinate, timestamp: location.timestamp,
            isApproximate: manager.accuracyAuthorization == .reducedAccuracy
        )
    }

    /// Resumes exactly once; the timeout and the delegate race to get here.
    private func finish(with location: CLLocation?) {
        guard let continuation else { return }
        self.continuation = nil
        // A failed request still leaves whatever the system last knew, which is
        // better than nothing as long as ``FixResolver`` checks how old it is.
        let best = location ?? manager.location.flatMap { usable($0) ? $0 : nil }
        continuation.resume(returning: Result(fix: best.map(measured), denied: false))
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        let last = locations.last
        Task { @MainActor in finish(with: last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in finish(with: nil) }
    }
}
