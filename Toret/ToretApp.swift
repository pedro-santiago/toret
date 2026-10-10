import SwiftUI

@main
struct ToretApp: App {
    init() {
        Typo.registerBundledFonts()
        // Has to be in place before the first notification can be delivered.
        NotificationRouter.shared.install()
        // Keeps the widgets' position fresh while the app is closed, and has to
        // exist before a location relaunch can deliver its event.
        BackgroundLocation.shared.install()
        // A walk the system left behind when the app was killed mid-route.
        Task { await WalkActivityController.shared.endOrphans() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // Turin is drawn in plaster and shutter green; there is no second
                // palette for dark mode, so the app keeps its own light.
                .preferredColorScheme(.light)
        }
    }
}
