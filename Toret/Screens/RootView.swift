import SwiftUI

/// The four tabs, the glass bar under them, and the compass over everything.
struct RootView: View {
    @State private var model = ToretModel()
    @State private var location = LocationProvider()
    @State private var router = NotificationRouter.shared
    @State private var community = Community.standard()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model

        ZStack(alignment: .bottom) {
            Group {
                switch model.tab {
                case .map: stack(.map) { MapScreen() }
                case .nearby: stack(.nearby) { NearbyScreen() }
                case .community: stack(.community) { CommunityScreen() }
                case .saved: stack(.saved) { SavedScreen() }
                case .settings: stack(.settings) { SettingsScreen() }
                }
            }

            ToretTabBar(selection: $model.tab) { tab in
                model.popToRoot(tab)
            }
        }
        .environment(model)
        .environment(location)
        .environment(community)
        .background(Palette.paper)
        .fullScreenCover(isPresented: $model.showingCompass) {
            CompassScreen()
                .environment(model)
                .environment(location)
        }
        .fullScreenCover(item: $model.walkingTo) { fountain in
            RouteScreen(fountain: fountain)
                .environment(model)
                .environment(location)
        }
        .task {
            location.start()
            // Publishes the last known fix to the widgets and arms the geofences,
            // both of which have to survive the app being closed.
            model.start()
            // What the community said while the app was closed reaches the pins
            // before the first refresh does.
            model.apply(summaries: community.summaries)
            openScreenFromLaunchArguments()
            community.startMonitoring()
            await community.refresh()
        }
        // Every distance and bearing in the app is measured from here, so one
        // fix re-derives the whole catalogue.
        .onChange(of: location.coordinate.latitude) { model.updateOrigin(location.coordinate) }
        .onChange(of: location.coordinate.longitude) { model.updateOrigin(location.coordinate) }
        // Tapping the proximity alert lands on the route to the fountain it
        // fired for, which is what its own copy promises.
        .onChange(of: router.pendingID) { openTappedNotification() }
        .onChange(of: community.summaries) { model.apply(summaries: community.summaries) }
        // A report's state expires with time and nothing else tells the pins.
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            community.recompute()
            Task { await community.refresh() }
        }
    }

    private func openTappedNotification() {
        guard let number = router.consume(),
              let fountain = model.fountains.first(where: { $0.id == number })
        else { return }
        model.tab = .map
        model.select(fountain)
        model.walkingTo = fountain
    }

    /// Jumps straight to a screen when the app is launched with
    /// `-toret-screen <mapa|perto|salvas|ajustes|bussola|detalhe|rota>`.
    ///
    /// Debug only, and the only way to capture the deeper screens from a script:
    /// the simulator has no way to drive a tap.
    private func openScreenFromLaunchArguments() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-toret-screen"),
              arguments.indices.contains(flag + 1)
        else { return }

        switch arguments[flag + 1] {
        case "perto": model.tab = .nearby
        case "relatos": model.tab = .community
        case "salvas": model.tab = .saved
        case "ajustes": model.tab = .settings
        case "bussola": model.showingCompass = true
        case "detalhe": model.push(.detail(model.selected), in: .map)
        case "rota": model.walkingTo = model.selected
        default: model.tab = .map
        }
        #endif
    }

    /// One navigation stack per tab, so each keeps its own place.
    private func stack<Content: View>(
        _ tab: Tab, @ViewBuilder root: () -> Content
    ) -> some View {
        @Bindable var model = model

        return NavigationStack(path: Binding(
            get: { model.path(for: tab) },
            set: { model.paths[tab] = $0 }
        )) {
            root()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case let .detail(fountain):
                        DetailScreen(fountain: fountain)
                            .environment(model)
                            .environment(location)
                            .environment(community)
                    }
                }
        }
    }
}

#Preview {
    RootView()
}
