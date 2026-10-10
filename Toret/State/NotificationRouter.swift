import Observation
import UserNotifications

/// What happens when the proximity alert is tapped.
///
/// The alert says "Toque para traçar a rota", and a notification that promises
/// something it does not do is worse than no notification: the next one gets
/// ignored. Tapping selects the fountain the geofence fired for and opens the
/// walking route on it.
@MainActor
@Observable
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    /// The plate number the user tapped through to, cleared once the root has
    /// acted on it.
    var pendingID: String?

    private override init() {
        super.init()
    }

    /// Called before the first notification can arrive.
    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func consume() -> String? {
        defer { pendingID = nil }
        return pendingID
    }

    // MARK: Delegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let number = response.notification.request.content.userInfo["fountain"] as? String
        await MainActor.run { pendingID = number }
    }

    /// The alert is about where you are *right now*, so it is worth showing even
    /// with the app open — the map may well be looking somewhere else.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
