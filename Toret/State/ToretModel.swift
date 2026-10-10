import CoreLocation
import MapKit
import SwiftUI

/// Which of the five tabs is showing.
enum Tab: Hashable, CaseIterable {
    case map, nearby, community, saved, settings

    var title: String {
        switch self {
        case .map: "Mapa"
        case .nearby: "Perto"
        case .community: "Relatos"
        case .saved: "Salvas"
        case .settings: "Ajustes"
        }
    }
}

/// Where a pushed screen sits in a tab's stack.
///
/// Walking is deliberately not here: it is presented full screen, because
/// turn-by-turn is a mode you leave rather than a page you go back from, and
/// nothing else should be competing for the display while you are moving.
enum Route: Hashable {
    case detail(Fountain)
}

/// The single source of truth, ported from the design document's `DCLogic`
/// component: a selection, an unwrapped compass bearing, and the handful of
/// derived readings every screen shares.
@MainActor
@Observable
final class ToretModel {
    /// Every fountain, measured from ``origin``, nearest first.
    ///
    /// Kept sorted rather than sorted on read: a dozen views ask for the nearest
    /// few on every frame, and there are 700 of them.
    private(set) var fountains: [Fountain]

    /// What the community has said, by fountain id.
    private(set) var summaries: [String: CommunitySummary] = [:]

    /// Where the distances are measured from.
    private(set) var origin: CLLocationCoordinate2D = Catalogue.anchor

    private(set) var selectedID: String

    /// Bumped on every selection so views can key their own transitions off it —
    /// the number counts on one curve, the pins resize on another, and the needle
    /// swings on a third, exactly as the CSS transitions did.
    private(set) var selectionToken: Int = 0

    /// The needle angle, *accumulated* rather than reduced to 0..<360.
    ///
    /// Interpolating 296° → 8° numerically would spin the needle three-quarters
    /// of the way round the dial to travel 72°. Adding the short-way delta to a
    /// running total makes the animation take the turn a real compass would.
    private(set) var needleAngle: Double = 0

    /// What the map is looking at.
    var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: Catalogue.anchor,
            span: MKCoordinateSpan(latitudeDelta: 0.011, longitudeDelta: 0.011)
        )
    )

    /// The part of the map on screen, so only the pins in view are drawn.
    var visibleRegion: MKCoordinateRegion?

    var activeFilters: Set<MapFilter> = [] { didSet { persist() } }
    var savedIDs: Set<String> = [] { didSet { persist() } }
    var searchText: String = ""

    /// "Bússola sempre visível" — the lock screen and widget follow you.
    ///
    /// This is the umbrella permission for everything that happens outside the
    /// app: with it off, the widgets stop being told where you are and the
    /// proximity alert stands down with them.
    var compassAlwaysVisible: Bool = true {
        didSet {
            persist()
            publishToWidgets()
            armAlerts(asking: compassAlwaysVisible)
        }
    }

    /// Whether to raise a notification when you walk within reach of water.
    var proximityAlerts: Bool = true {
        didSet {
            persist()
            armAlerts(asking: proximityAlerts)
        }
    }

    /// True once a real fix has replaced the Turin anchor.
    ///
    /// The widgets are only told a position that was actually measured — a widget
    /// reading "84 m" from the anchor would be a picture of the design, not an
    /// answer to where the user is standing.
    private(set) var hasFix = false

    private var alertsArmed: Bool { proximityAlerts && compassAlwaysVisible }

    /// True while `init` is loading the stored preferences into place.
    ///
    /// `@Observable` turns these into computed properties over stored backing,
    /// and a backing property that already has a default value is *assigned*
    /// rather than initialised — so `didSet` fires during `init`. Without this
    /// flag the model writes its preferences back before it has finished reading
    /// them, and stamps the selection as whichever fountain happens to be first
    /// in the catalogue.
    @ObservationIgnored private var isRestoring = true

    /// Where the preferences and the widgets' fix are written.
    @ObservationIgnored private let defaults: UserDefaults

    var tab: Tab = .map
    var paths: [Tab: [Route]] = [:]
    var showingCompass = false
    /// The fountain being walked to, if any. Drives the full-screen route mode.
    var walkingTo: Fountain?

    init(preferences: Preferences = .load(), defaults: UserDefaults = Store.defaults) {
        self.defaults = defaults
        let all = Catalogue.fountains().sorted { $0.distance < $1.distance }
        fountains = all
        selectedID = all.first?.id ?? ""
        savedIDs = preferences.savedIDs
        activeFilters = Set(preferences.filters.compactMap(MapFilter.init(rawValue:)))
        compassAlwaysVisible = preferences.compassAlwaysVisible
        proximityAlerts = preferences.proximityAlerts

        // Reopen on the fountain that was showing; failing that, on the nearest
        // one, because on a first launch the only thing the user wants is the
        // closest water.
        if let restored = preferences.selectedID, all.contains(where: { $0.id == restored }) {
            selectedID = restored
        }
        let chosen = all.first { $0.id == selectedID }
        needleAngle = chosen?.bearing ?? 0
        camera = .region(
            MKCoordinateRegion(
                center: chosen?.coordinate ?? Catalogue.anchor,
                span: MKCoordinateSpan(latitudeDelta: 0.011, longitudeDelta: 0.011)
            )
        )
        isRestoring = false
    }

    /// Arms everything that reaches outside the app. Called once, from the root.
    func start() {
        publishToWidgets()
        armAlerts()
    }

    /// Re-measures every fountain against a new fix and swings the needle to match.
    func updateOrigin(_ coordinate: CLLocationCoordinate2D) {
        // The first fix counts even when it lands exactly on the anchor: what
        // the widgets are waiting for is a *measured* position, not a different
        // one from the one they already have.
        if !hasFix {
            hasFix = true
            publishToWidgets()
        }
        guard coordinate.latitude != origin.latitude
            || coordinate.longitude != origin.longitude else { return }
        origin = coordinate
        remeasure()
        needleAngle += Bearing.shortestDelta(from: needleAngle, to: selected.bearing)
        publishToWidgets()
        // The geofences are drawn round the nearest fountains, so they move with
        // the user rather than staying where the app was opened.
        armAlerts()
    }

    /// Folds the community's latest word into every fountain.
    func apply(summaries: [String: CommunitySummary]) {
        guard summaries != self.summaries else { return }
        self.summaries = summaries
        fountains = fountains.map { $0.with(community: summaries[$0.id] ?? .empty) }
        armAlerts()
    }

    private func remeasure() {
        fountains = fountains
            .map { $0.relocated(to: origin) }
            .sorted { $0.distance < $1.distance }
    }

    // MARK: Selection

    var selected: Fountain { fountains.first { $0.id == selectedID } ?? fountains[0] }

    func select(_ fountain: Fountain) {
        guard fountain.id != selectedID,
              let current = fountains.first(where: { $0.id == fountain.id })
        else { return }
        camera = .region(
            MKCoordinateRegion(
                center: current.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.009, longitudeDelta: 0.009)
            )
        )
        needleAngle += Bearing.shortestDelta(from: needleAngle, to: current.bearing)
        selectedID = current.id
        selectionToken += 1
        persist()
    }

    // MARK: Derived readings

    /// Every fountain, nearest first.
    var byDistance: [Fountain] { fountains }

    /// The three the compass panel lists under the dial.
    var nearest3: [Fountain] { Array(fountains.prefix(3)) }

    /// The ones "Perto de mim" opens with.
    var nearest7: [Fountain] { Array(fountains.prefix(7)) }

    /// The nearest `count` that have not been reported dry — the ones worth a walk.
    func nearestUsable(_ count: Int) -> [Fountain] {
        Array(fountains.lazy.filter { $0.state.isUsable }.prefix(count))
    }

    /// Whether the fountain the needle is pointing at is in fact the nearest one.
    ///
    /// It is on a first launch and stops being one the moment the user picks
    /// another pin or walks past something closer — and the compass label has to
    /// stop claiming otherwise, or the one number the app exists to give you is
    /// captioned with a lie.
    var selectedIsNearest: Bool { selected.id == fountains.first?.id }

    /// Fountains within the design's half-kilometre horizon.
    var withinHalfKilometre: Int { fountains.count { $0.distance <= 500 } }

    /// The bearing spoken as something you can do with your body.
    var orientation: String { Landmark.orientation(for: selected.bearing, from: origin) }

    /// The skyline as seen from here — the compass ring's labels.
    var landmarks: [Landmark] { Landmark.ring(from: origin) }

    /// The silhouettes drawn over the map.
    var mapLandmarks: [Landmark] { Landmark.onMap(from: origin) }

    func matchesFilters(_ fountain: Fountain) -> Bool {
        activeFilters.allSatisfy { $0.matches(fountain) }
    }

    /// The pins worth drawing: what is on screen, capped, plus the selected and
    /// the saved. Seven hundred annotations is what makes a SwiftUI map stutter;
    /// the few dozen in view are what you can tap anyway.
    var mapPins: [Fountain] {
        let limit = 220
        guard let region = visibleRegion else { return Array(fountains.prefix(limit)) }
        let latitudeReach = region.span.latitudeDelta * 0.6
        let longitudeReach = region.span.longitudeDelta * 0.6
        var pins = fountains.filter {
            abs($0.latitude - region.center.latitude) <= latitudeReach
                && abs($0.longitude - region.center.longitude) <= longitudeReach
        }
        if pins.count > limit {
            let centre = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
            pins = Array(
                pins.sorted {
                    CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: centre)
                        < CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: centre)
                }.prefix(limit)
            )
        }
        for extra in [selected] + savedFountains where !pins.contains(extra) {
            pins.append(extra)
        }
        return pins
    }

    /// Fountains matching what was typed in the search field, nearest first.
    var searchResults: [Fountain] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard query.count >= 2 else { return [] }
        return Array(fountains.lazy.filter { $0.searchHaystack.contains(query) }.prefix(8))
    }

    // MARK: Filters and saving

    func toggle(_ filter: MapFilter) {
        if activeFilters.contains(filter) {
            activeFilters.remove(filter)
        } else {
            activeFilters.insert(filter)
        }
    }

    func isSaved(_ fountain: Fountain) -> Bool { savedIDs.contains(fountain.id) }

    func toggleSaved(_ fountain: Fountain) {
        if savedIDs.contains(fountain.id) {
            savedIDs.remove(fountain.id)
        } else {
            savedIDs.insert(fountain.id)
        }
    }

    var savedFountains: [Fountain] {
        fountains.filter { savedIDs.contains($0.id) }
    }

    // MARK: Navigation

    func path(for tab: Tab) -> [Route] { paths[tab] ?? [] }

    func push(_ route: Route, in tab: Tab) {
        paths[tab, default: []].append(route)
    }

    func popToRoot(_ tab: Tab) { paths[tab] = [] }

    // MARK: Persistence

    private func persist() {
        guard !isRestoring else { return }
        Preferences(
            savedIDs: savedIDs,
            filters: Set(activeFilters.map(\.rawValue)),
            compassAlwaysVisible: compassAlwaysVisible,
            proximityAlerts: proximityAlerts,
            selectedID: selectedID
        ).save(to: defaults)
    }

    /// `asking` is only ever true when the user just flipped one of the two
    /// switches; startup and location fixes arm silently or not at all.
    private func armAlerts(asking: Bool = false) {
        guard !isRestoring else { return }
        ProximityAlerts.shared.reconcile(
            enabled: alertsArmed, fountains: fountains, asking: asking
        )
    }

    private func publishToWidgets() {
        guard !isRestoring else { return }
        WidgetBridge.publish(
            origin: compassAlwaysVisible && hasFix ? origin : nil, to: defaults
        )
    }
}
