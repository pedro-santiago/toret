import CoreLocation
import Foundation
import WidgetKit

/// The one container the app and its widgets both write to.
///
/// Everything shared crosses this boundary: the settings the user changed, the
/// fountains they saved, and — the reason the widgets exist at all — the last
/// position the app measured from. Without the group the widget can only ever
/// show the catalogue from the middle of Turin, which is a picture rather than
/// an answer.
enum Store {
    static let appGroup = "group.br.tec.nuance.toret"

    /// The shared suite, or the target's own defaults if the group is missing.
    ///
    /// A build without the entitlement still runs and still remembers things;
    /// only the widgets fall back to the anchor, which is the honest failure.
    /// Computed rather than stored: `UserDefaults` is not `Sendable`, and the
    /// suite is cheap — the framework keeps one instance per name behind this.
    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    enum Key {
        static let saved = "toret.saved"
        static let filters = "toret.filters"
        static let compassAlwaysVisible = "toret.compass.alwaysVisible"
        static let proximityAlerts = "toret.alerts.proximity"
        static let selected = "toret.selected"
        static let originLatitude = "toret.origin.lat"
        static let originLongitude = "toret.origin.lon"
        static let originDate = "toret.origin.date"
    }
}

// MARK: - Preferences

/// What the app remembers between launches.
///
/// Deliberately small: the saved fountains, the two switches, the chips, and
/// which fountain was open. Nothing here is a cache — every one of these is a
/// decision the user made, and losing it on relaunch would be a bug they notice.
struct Preferences: Equatable, Sendable {
    var savedIDs: Set<String>
    var filters: Set<String>
    var compassAlwaysVisible: Bool
    var proximityAlerts: Bool
    var selectedID: String?

    /// The state a fresh install opens in: nothing saved, no filter on, both
    /// switches live.
    static let initial = Preferences(
        savedIDs: [],
        filters: [],
        compassAlwaysVisible: true,
        proximityAlerts: true,
        selectedID: nil
    )

    static func load(from defaults: UserDefaults = Store.defaults) -> Preferences {
        // A first launch has no keys at all; a second launch that turned both
        // switches off has them set to false. `object(forKey:)` is what tells
        // the two apart — `bool(forKey:)` alone would keep switching them back on.
        guard defaults.object(forKey: Store.Key.compassAlwaysVisible) != nil
            || defaults.object(forKey: Store.Key.saved) != nil
        else { return .initial }

        return Preferences(
            savedIDs: Set(defaults.stringArray(forKey: Store.Key.saved) ?? []),
            filters: Set(defaults.stringArray(forKey: Store.Key.filters) ?? []),
            compassAlwaysVisible: defaults.object(forKey: Store.Key.compassAlwaysVisible) as? Bool ?? true,
            proximityAlerts: defaults.object(forKey: Store.Key.proximityAlerts) as? Bool ?? true,
            selectedID: defaults.string(forKey: Store.Key.selected)
        )
    }

    func save(to defaults: UserDefaults = Store.defaults) {
        defaults.set(Array(savedIDs), forKey: Store.Key.saved)
        defaults.set(Array(filters), forKey: Store.Key.filters)
        defaults.set(compassAlwaysVisible, forKey: Store.Key.compassAlwaysVisible)
        defaults.set(proximityAlerts, forKey: Store.Key.proximityAlerts)
        defaults.set(selectedID, forKey: Store.Key.selected)
    }
}

// MARK: - Widget bridge

/// The position the widgets measure from.
///
/// The widget carries the same catalogue as the app, so the only thing it is
/// missing is where you are standing. Publishing the fix — and nothing else —
/// keeps the two in step without a second copy of the data to go stale.
enum WidgetBridge {
    /// How long a published fix stays believable.
    ///
    /// A widget claiming "84 m" from yesterday's walk is worse than one that
    /// admits it is showing the city centre, so a stale fix is discarded rather
    /// than displayed.
    static let freshness: TimeInterval = 6 * 3600

    /// Writes the fix the widgets should use, or clears it when the user has
    /// told the compass to stay inside the app.
    static func publish(
        origin: CLLocationCoordinate2D?, to defaults: UserDefaults = Store.defaults
    ) {
        if let origin {
            defaults.set(origin.latitude, forKey: Store.Key.originLatitude)
            defaults.set(origin.longitude, forKey: Store.Key.originLongitude)
            defaults.set(Date.now.timeIntervalSince1970, forKey: Store.Key.originDate)
        } else {
            defaults.removeObject(forKey: Store.Key.originLatitude)
            defaults.removeObject(forKey: Store.Key.originLongitude)
            defaults.removeObject(forKey: Store.Key.originDate)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The published fix, if there is a recent one.
    static func origin(from defaults: UserDefaults = Store.defaults) -> CLLocationCoordinate2D? {
        guard let stamp = defaults.object(forKey: Store.Key.originDate) as? TimeInterval,
              Date.now.timeIntervalSince1970 - stamp < freshness,
              let latitude = defaults.object(forKey: Store.Key.originLatitude) as? CLLocationDegrees,
              let longitude = defaults.object(forKey: Store.Key.originLongitude) as? CLLocationDegrees
        else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// The fountains the user saved, for the widget to mark.
    static func savedIDs(from defaults: UserDefaults = Store.defaults) -> Set<String> {
        Set(defaults.stringArray(forKey: Store.Key.saved) ?? [])
    }
}
