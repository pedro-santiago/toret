import SwiftUI

/// The four tabs, the glass bar under them, and the compass over everything.
struct RootView: View {
    @State private var model = ToretModel()
    @State private var location = LocationProvider()
    @State private var router = NotificationRouter.shared
    @State private var community = Community.standard()
    @State private var conditions = ConditionsStore.standard()
    @State private var showingSkyline = false
    @State private var showingEmpties = false
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
        // Inside the environment calls: the modifier reads the model and the
        // community from it, and sees only what is injected *outside* it.
        .modifier(CommunityHooks())
        .modifier(ConditionsHooks(store: conditions))
        .environment(model)
        .environment(location)
        .environment(community)
        .environment(conditions)
        .background(Palette.paper)
        .overlay { LaunchOverlay() }
        .modifier(SkylineGalleryHook(isPresented: $showingSkyline))
        .modifier(EmptyGalleryHook(isPresented: $showingEmpties))
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
            openScreenFromLaunchArguments()
        }
        // Every distance and bearing in the app is measured from here, so one
        // fix re-derives the whole catalogue.
        .onChange(of: location.coordinate.latitude) { model.updateOrigin(location.coordinate) }
        .onChange(of: location.coordinate.longitude) { model.updateOrigin(location.coordinate) }
        // Tapping the proximity alert lands on the route to the fountain it
        // fired for, which is what its own copy promises.
        .onChange(of: router.pendingID) { openTappedNotification() }
        // Widgets, controls, Siri and the Live Activity all arrive as `toret://`.
        .onOpenURL { url in open(url) }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            // Siri and Shortcuts may have saved a fountain while the app slept.
            model.reloadExternalPreferences()
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

    /// Where a `toret://` link from a widget, control, shortcut or Live Activity goes.
    private func open(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        Task {
            switch link {
            case let .fountain(id):
                guard let fountain = model.fountains.first(where: { $0.id == id }) else { return }
                model.showingCompass = false
                model.walkingTo = nil
                model.tab = .map
                model.popToRoot(.map)
                model.select(fountain)
                model.push(.detail(fountain), in: .map)
            case let .route(id):
                guard let fountain = model.fountains.first(where: { $0.id == id }) else { return }
                model.showingCompass = false
                model.select(fountain)
                model.walkingTo = fountain
            case .routeToNearest:
                // "Nearest" has to be measured from the user, not from wherever
                // the model was standing when the app was cold-launched.
                await waitForFix()
                guard let fountain = model.nearestUsable(1).first else { return }
                model.showingCompass = false
                model.select(fountain)
                model.walkingTo = fountain
            case let .compass(nearest):
                if nearest {
                    await waitForFix()
                    if let fountain = model.nearestUsable(1).first { model.select(fountain) }
                }
                model.walkingTo = nil
                model.showingCompass = true
            }
        }
    }

    /// Gives a cold launch up to three seconds to get its first fix, and no time
    /// at all when there is no fix coming (denied, or outside Turin).
    private func waitForFix() async {
        for _ in 0 ..< 30 {
            guard location.status == .searching else { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        // One more tick for the fix to reach the model's distances.
        try? await Task.sleep(for: .milliseconds(60))
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
        case "skyline": showingSkyline = true
        case "vazios": showingEmpties = true
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
                            .environment(conditions)
                    }
                }
        }
    }
}

#Preview {
    RootView()
}
