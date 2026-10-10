import CoreLocation
import Observation

/// Why the distances on screen are measured from where they are.
///
/// The app has to be useful to someone who has not granted a permission, who is
/// not in Turin, or who has not got a fix yet. Each of those is a different
/// sentence to say to them, and none of them may be a silent fallback — a distance
/// that is quietly measured from somewhere else is a lie.
enum LocationStatus: Equatable, Sendable {
    /// The permission prompt has not been answered yet.
    case asking
    /// Authorised, waiting for the first fix.
    case searching
    /// A real fix inside Turin.
    case live
    /// A real fix, but Precise Location is off: good for a neighbourhood, not a street.
    case approximate
    /// The user said no.
    case denied
    /// Screen Time or a profile forbids it.
    case restricted
    /// A real fix, far from the catalogue: distances are measured from the old town.
    case outsideTurin(kilometres: Int)

    /// Whether the distances on screen come from the user's own position.
    var isMeasuringFromUser: Bool {
        switch self {
        case .live, .approximate: true
        default: false
        }
    }
}

/// Where you are, and which way you are facing.
///
/// Two separate signals doing two separate jobs: the fix decides the distances,
/// and the heading decides which way the dial turns.
@MainActor
@Observable
final class LocationProvider: NSObject {
    /// Where the distances are measured from: the user when they are in Turin,
    /// the centre of the old town otherwise.
    private(set) var coordinate: CLLocationCoordinate2D = Catalogue.anchor
    /// The last real fix, wherever it was.
    private(set) var rawCoordinate: CLLocationCoordinate2D?
    /// Device heading in degrees clockwise from true north, when available.
    private(set) var heading: Double?
    /// How far off the heading may be, in degrees. Nil when unknown.
    private(set) var headingAccuracy: Double?
    private(set) var authorization: CLAuthorizationStatus
    private(set) var accuracy: CLAccuracyAuthorization

    /// True while the coordinate is the Turin anchor rather than a real fix.
    private(set) var isAnchored = true

    private let manager = CLLocationManager()

    override init() {
        authorization = manager.authorizationStatus
        accuracy = manager.accuracyAuthorization
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // Ten metres is a fountain's width; anything finer just churns the UI.
        manager.distanceFilter = 10
        manager.headingFilter = 3
        manager.activityType = .fitness
    }

    var status: LocationStatus {
        switch authorization {
        case .notDetermined: return .asking
        case .denied: return .denied
        case .restricted: return .restricted
        default: break
        }
        guard let rawCoordinate else { return .searching }
        if !Catalogue.covers(rawCoordinate) {
            return .outsideTurin(
                kilometres: Int((Catalogue.distanceToCentre(from: rawCoordinate) / 1000).rounded())
            )
        }
        return accuracy == .reducedAccuracy ? .approximate : .live
    }

    /// The compass needs a trustworthy heading to turn the dial; a wildly
    /// inaccurate one is worse than a north-up chart.
    var hasUsableHeading: Bool {
        guard heading != nil else { return false }
        guard let headingAccuracy else { return true }
        return headingAccuracy >= 0 && headingAccuracy <= 35
    }

    func start() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
        #if DEBUG
        // `-toret-heading 40` pins the heading, because the simulator has no
        // magnetometer and the turning dial could otherwise never be looked at.
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-toret-heading"),
           arguments.indices.contains(flag + 1), let degrees = Double(arguments[flag + 1]) {
            heading = degrees
            headingAccuracy = 5
            return
        }
        #endif
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    /// Asks for a single fresh fix, for the moments a stale one would mislead —
    /// the app coming back to the foreground after a bus ride.
    func refresh() {
        manager.requestLocation()
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let accuracy = manager.accuracyAuthorization
        Task { @MainActor in
            authorization = status
            self.accuracy = accuracy
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                start()
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        guard let fix = locations.last, fix.horizontalAccuracy >= 0 else { return }
        Task { @MainActor in
            rawCoordinate = fix.coordinate
            // The catalogue covers Turin. A fix from anywhere else is real but
            // useless here, so distances stay on the anchor and `status` says so,
            // rather than reporting that the nearest drinking fountain is 900 km away.
            guard Catalogue.covers(fix.coordinate) else {
                coordinate = Catalogue.anchor
                isAnchored = true
                return
            }
            coordinate = fix.coordinate
            isAnchored = false
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading
    ) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        let accuracy = newHeading.headingAccuracy
        Task { @MainActor in
            heading = value >= 0 ? value : nil
            headingAccuracy = accuracy
        }
    }

    /// Lets iOS show its figure-of-eight calibration sheet when the magnetometer
    /// is disturbed — a compass app that never offers it just points wrongly.
    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A failed one-shot request or a lost fix leaves the previous position in
        // place; `status` already says "searching" until the first one arrives.
    }
}

extension LocationStatus {
    /// Why the distances on screen are what they are, in one sentence — nil when
    /// they are measured from the user and nothing needs saying.
    ///
    /// The same words the map's banner uses, so the compass and the map never
    /// explain the one fact two ways.
    var explanation: String? {
        switch self {
        case .asking, .live:
            nil
        case .searching:
            String(localized: "Procurando a sua posição…")
        case .denied:
            String(localized: "Localização desligada. Distâncias medidas a partir da Piazza San Carlo.")
        case .restricted:
            String(localized: "Localização bloqueada neste aparelho. Distâncias medidas a partir da Piazza San Carlo.")
        case .approximate:
            String(localized: "Localização aproximada. Ative a posição precisa para distâncias exatas.")
        case let .outsideTurin(kilometres):
            String(localized: "Você está a \(Formatting.integer(kilometres)) km de Turim. Distâncias medidas a partir da Piazza San Carlo.")
        }
    }
}
