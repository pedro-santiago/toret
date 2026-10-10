import CoreLocation
import UserNotifications

/// The lock-screen alert from the design, fired by a real geofence.
///
/// "Fonte a 100 m — Toret · Via Po." The distance and
/// the state are both in the first two lines, because the whole value of the
/// alert is deciding, without unlocking anything, whether it is worth the detour.
///
/// The condition is a ring drawn round each of the nearest running fountains and
/// handed to `CLMonitor`, so the alert arrives when you walk into range — which
/// is the only moment it is worth anything. The rings are redrawn on every fix,
/// so they follow the user across the city instead of staying where the app was
/// opened.
@MainActor
final class ProximityAlerts {
    static let shared = ProximityAlerts()

    static let categoryIdentifier = "TORET_PROXIMITY"

    /// How close counts as "passing by".
    ///
    /// A hundred metres is a little over a minute's walk and about one block of
    /// the Turin grid — near enough that the detour is free, far enough that the
    /// notification arrives while you can still act on it.
    private static let radius: CLLocationDistance = 100

    /// iOS keeps a hard cap on monitored regions per app; the nearest few are the
    /// only ones that can plausibly fire before the next fix redraws them anyway.
    private static let maximumRegions = 8

    private static let monitorName = "toret.proximity"
    private static func identifier(for fountain: Fountain) -> String { "fonte-\(fountain.id)" }

    private let manager = CLLocationManager()
    private var monitor: CLMonitor?
    private var watcher: Task<Void, Never>?
    private var arming: Task<Void, Never>?
    /// What each armed ring is round, so an event can be read back as a fountain.
    private var armed: [String: Fountain] = [:]

    private init() {}

    /// Matches the geofences to the settings and to the current catalogue.
    ///
    /// `asking` is what separates the user flipping the switch from the app
    /// starting up. Only the first is allowed to raise a permission dialog: a
    /// notification prompt on top of the location prompt, before the user has
    /// seen a single fountain, is how an app gets both of them denied.
    func reconcile(enabled: Bool, fountains: [Fountain], asking: Bool = false) {
        arming?.cancel()
        guard enabled else {
            arming = Task { await disarm() }
            return
        }
        let targets = Array(
            fountains
                .filter { $0.state != .dry }
                .sorted { $0.distance < $1.distance }
                .prefix(Self.maximumRegions)
        )
        arming = Task { await arm(targets, asking: asking) }
    }

    // MARK: Arming

    private func arm(_ fountains: [Fountain], asking: Bool) async {
        guard await authorise(asking: asking) else { return }

        let monitor: CLMonitor
        if let existing = self.monitor {
            monitor = existing
        } else {
            monitor = await CLMonitor(Self.monitorName)
            self.monitor = monitor
        }

        let wanted = Dictionary(
            uniqueKeysWithValues: fountains.map { (Self.identifier(for: $0), $0) }
        )
        let existing = Set(await monitor.identifiers)

        for identifier in existing where wanted[identifier] == nil {
            await monitor.remove(identifier)
        }
        for (identifier, fountain) in wanted where !existing.contains(identifier) {
            // `.unsatisfied` is the assumption that makes this useful: the ring
            // starts out as "you are not there yet", so walking into it is an
            // event rather than a silent match.
            await monitor.add(
                CLMonitor.CircularGeographicCondition(
                    center: fountain.coordinate, radius: Self.radius
                ),
                identifier: identifier,
                assuming: .unsatisfied
            )
        }
        armed = wanted
        watch(monitor)
    }

    private func disarm() async {
        watcher?.cancel()
        watcher = nil
        armed = [:]
        guard let monitor else { return }
        for identifier in await monitor.identifiers {
            await monitor.remove(identifier)
        }
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    private func watch(_ monitor: CLMonitor) {
        guard watcher == nil else { return }
        watcher = Task { [weak self] in
            do {
                for try await event in await monitor.events {
                    guard !Task.isCancelled else { return }
                    guard event.state == .satisfied else { continue }
                    await self?.announce(event.identifier)
                }
            } catch {
                // The stream ends when monitoring is torn down or authorisation
                // is withdrawn. Either way the geofences are gone; reconciling
                // again is the settings screen's job, not this task's.
                self?.watcher = nil
            }
        }
    }

    // MARK: Firing

    private func announce(_ identifier: String) async {
        guard let fountain = armed[identifier] else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Fonte a \(Int(Self.radius)) m")
        // The app does not know whether the water is running; it says what the
        // community last reported, and nothing when nobody has. Two whole
        // sentences rather than one with a hole in it, so every language can
        // order the words its own way.
        let plate = fountain.plateTitle
        let place = fountain.place
        if fountain.state == .unknown {
            content.body = String(localized: "\(plate) · \(place). Toque para traçar a rota.")
        } else {
            let state = fountain.state.label.lowercased(with: .autoupdatingCurrent)
            content.body = String(localized: "\(plate) · \(place). Relato recente: \(state). Toque para traçar a rota.")
        }
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["fountain": fountain.id]
        content.sound = .default
        content.interruptionLevel = .active

        // No trigger: the geofence already decided when.
        let request = UNNotificationRequest(
            identifier: identifier, content: content, trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: Permission

    private func authorise(asking: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .notDetermined:
            guard asking,
                  let granted = try? await center.requestAuthorization(options: [.alert, .sound]),
                  granted
            else { return false }
        default:
            return false
        }

        // A geofence that only works with the app open is a worse feature than
        // no geofence, so this is the one place the app asks for "sempre" — and
        // only once the user has asked for the alert.
        switch manager.authorizationStatus {
        case .authorizedAlways:
            return true
        case .authorizedWhenInUse:
            if asking { manager.requestAlwaysAuthorization() }
            return true
        case .notDetermined:
            if asking { manager.requestAlwaysAuthorization() }
            return false
        default:
            return false
        }
    }
}
