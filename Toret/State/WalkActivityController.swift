@preconcurrency import ActivityKit
import CoreLocation
import UIKit

/// Carries the walk onto the Lock Screen and the Dynamic Island, so the phone can
/// stay in a pocket for the whole way.
///
/// It keeps its own location manager rather than borrowing the app's: a walk has
/// to go on updating with the screen off, which needs background updates and the
/// blue indicator that goes with them — things the rest of the app has no reason
/// to switch on. Both are on only while a walk is, and off the moment it ends.
@MainActor
final class WalkActivityController: NSObject {
    static let shared = WalkActivityController()

    private typealias State = WalkActivityAttributes.ContentState

    /// How long the arrival stays on the Lock Screen before it clears itself.
    private static let arrivalLinger: TimeInterval = 90
    /// An update older than this is flagged as out of date by the system.
    private static let staleAfter: TimeInterval = 5 * 60

    private let manager = CLLocationManager()
    private var activity: Activity<WalkActivityAttributes>?
    private var destination: Fountain?
    private var lastState: State?
    private var lastUpdate: Date?
    private var heading: Double?
    private var position: CLLocation?

    /// What the route screen last worked out, so the figure shown is the walk's
    /// own distance rather than the straight line.
    private var routeRemaining: Int?
    private var routeToNextTurn: Int?
    private var routeInstruction = ""
    private var routedFrom: CLLocationCoordinate2D?

    private override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.headingFilter = 8
    }

    var isWalking: Bool { activity != nil }

    // MARK: Lifecycle

    /// Starts the activity and the location updates that feed it.
    func begin(to fountain: Fountain, from origin: CLLocationCoordinate2D) {
        end()
        destination = fountain
        routeRemaining = nil
        routeToNextTurn = nil
        routeInstruction = ""
        routedFrom = nil
        position = CLLocation(latitude: origin.latitude, longitude: origin.longitude)

        startLocationUpdates()

        // Switched off in Ajustes > Toret, or on an iPad: the walk still works,
        // it just has nowhere else to appear.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let initial = makeState(arrived: false)
        lastState = initial
        lastUpdate = .now
        activity = try? Activity.request(
            attributes: WalkActivityAttributes(
                fountainID: fountain.id, fountainName: fountain.place, zone: fountain.zone
            ),
            content: .init(state: initial, staleDate: Date.now.addingTimeInterval(Self.staleAfter)),
            pushType: nil
        )
    }

    /// The route screen reports every recalculation, so "metres left" follows the
    /// streets rather than the crow.
    func routeDidChange(
        remaining: Int?, toNextTurn: Int, instruction: String,
        routedFrom origin: CLLocationCoordinate2D
    ) {
        guard destination != nil else { return }
        routeRemaining = remaining
        routeToNextTurn = toNextTurn
        routeInstruction = instruction
        routedFrom = origin
        publish()
    }

    /// Ends the walk early: the activity clears at once, because "you are 120 m
    /// away" is a lie the moment the route is closed.
    func end(immediately: Bool = true) {
        let finished = activity
        stopTracking()
        guard let finished else { return }
        Task { await finished.end(nil, dismissalPolicy: .immediate) }
    }

    private func stopTracking() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        activity = nil
        destination = nil
        lastState = nil
        lastUpdate = nil
    }

    /// Arrival: the alert lights the Lock Screen, then the activity lingers a
    /// minute and a half so the last thing on it is "you are there".
    private func finish(_ finished: Activity<WalkActivityAttributes>, with state: State, place: String) {
        stopTracking()
        let alert = AlertConfiguration(
            title: LocalizedStringResource("Você chegou"),
            body: LocalizedStringResource(stringLiteral: place),
            sound: .default
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            let content = ActivityContent(state: state, staleDate: nil)
            await finished.update(content, alertConfiguration: alert)
            await finished.end(
                content, dismissalPolicy: .after(.now.addingTimeInterval(Self.arrivalLinger))
            )
        }
    }

    /// Clears anything an earlier launch left behind — a Live Activity outlives
    /// the process that started it, and one with nobody updating it only lies.
    func endOrphans() async {
        for orphan in Activity<WalkActivityAttributes>.activities where orphan.id != activity?.id {
            await orphan.end(nil, dismissalPolicy: .immediate)
        }
    }

    // MARK: Location

    private func startLocationUpdates() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            break
        default:
            return
        }
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    // MARK: Publishing

    private func makeState(arrived: Bool) -> State {
        guard let destination else {
            return State(
                remaining: 0, toNextTurn: 0, instruction: "", minutes: 1,
                bearing: 0, heading: nil, arrived: arrived
            )
        }
        let target = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let straight = position?.distance(from: target) ?? Double(destination.distance)
        let walked = routedFrom.flatMap { origin in
            position?.distance(
                from: CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            )
        } ?? 0
        let remaining = arrived ? 0 : WalkProgress.remaining(
            routeRemaining: routeRemaining, walkedSinceRoute: walked, straightLine: straight
        )
        let bearing = position.map {
            Bearing.forwardAzimuth(from: $0.coordinate, to: destination.coordinate)
        } ?? destination.bearing
        return State(
            remaining: remaining,
            toNextTurn: arrived ? 0 : min(remaining, routeToNextTurn ?? remaining),
            instruction: arrived
                ? String(localized: "Você chegou")
                : (routeInstruction.isEmpty ? String(localized: "Siga na direção da fonte") : routeInstruction),
            minutes: WalkProgress.minutes(forRemaining: remaining),
            bearing: bearing,
            heading: heading,
            arrived: arrived
        )
    }

    private func publish() {
        guard let activity, let destination else { return }

        let target = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let straight = position?.distance(from: target) ?? .infinity
        let arrived = WalkProgress.hasArrived(
            straightLine: straight, accuracy: position?.horizontalAccuracy
        )
        let next = makeState(arrived: arrived)
        guard WalkProgress.isWorthPublishing(
            previous: lastState, next: next, lastUpdate: lastUpdate
        ) else { return }

        lastState = next
        lastUpdate = .now

        if arrived {
            finish(activity, with: next, place: destination.place)
        } else {
            let content = ActivityContent(
                state: next, staleDate: Date.now.addingTimeInterval(Self.staleAfter)
            )
            Task { await activity.update(content) }
        }
    }
}

extension WalkActivityController: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        guard let fix = locations.last, fix.horizontalAccuracy >= 0 else { return }
        Task { @MainActor in
            position = fix
            publish()
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading
    ) {
        // A magnetometer reading that is off by more than 35° turns the needle
        // the wrong way; better to fall back to a north-up needle, labelled.
        let usable = newHeading.headingAccuracy >= 0 && newHeading.headingAccuracy <= 35
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            heading = usable && value >= 0 ? value : nil
            publish()
        }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        false
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
