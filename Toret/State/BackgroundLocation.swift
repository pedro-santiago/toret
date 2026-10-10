import CoreLocation
import Foundation
import WidgetKit

/// Keeps the widgets honest while the app is closed.
///
/// A widget can only measure from where the app last said you were. With the
/// user's "Bússola sempre visível" switch on and "Sempre" authorised, iOS wakes
/// the app on a significant change — roughly every few hundred metres, on cell
/// towers, at almost no battery cost — and this publishes the new position and
/// reloads the timelines. With the switch off nothing is monitored and the
/// published fix is cleared, the same promise the setting makes.
///
/// A relaunch for a location event gives the app a moment to create a location
/// manager and start monitoring again, which is why this is installed from
/// `ToretApp.init` rather than from a view.
@MainActor
final class BackgroundLocation: NSObject {
    static let shared = BackgroundLocation()

    private let manager = CLLocationManager()
    private var isMonitoring = false
    private var defaultsObserver: NSObjectProtocol?

    private override init() { super.init() }

    /// Called once, before any scene exists.
    func install() {
        guard defaultsObserver == nil else { return }
        manager.delegate = self
        // The user's switch lives in the shared container; following its change
        // notification means the toggle in Ajustes takes effect immediately
        // without this object knowing about the settings screen.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
        reconcile()
    }

    /// Whether this configuration should be watching for significant changes.
    nonisolated static func shouldMonitor(
        compassAlwaysVisible: Bool, authorization: CLAuthorizationStatus
    ) -> Bool {
        compassAlwaysVisible && authorization == .authorizedAlways
    }

    private func reconcile() {
        let wanted = Self.shouldMonitor(
            compassAlwaysVisible: Preferences.load().compassAlwaysVisible,
            authorization: manager.authorizationStatus
        ) && CLLocationManager.significantLocationChangeMonitoringAvailable()

        switch (wanted, isMonitoring) {
        case (true, false):
            manager.startMonitoringSignificantLocationChanges()
            isMonitoring = true
        case (false, true):
            manager.stopMonitoringSignificantLocationChanges()
            isMonitoring = false
        default:
            break
        }
    }
}

extension BackgroundLocation: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in reconcile() }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        guard let fix = locations.last, fix.horizontalAccuracy >= 0 else { return }
        let coordinate = fix.coordinate
        Task { @MainActor in
            guard Preferences.load().compassAlwaysVisible else { return }
            // Published as measured, even from far away: the widget decides what
            // "far from Turin" means, and says so, rather than going blank.
            WidgetBridge.publish(origin: coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
