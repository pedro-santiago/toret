import CoreLocation
import Foundation
import Testing

@testable import Toret

// MARK: - Deep links

@Suite("Deep links")
struct DeepLinkTests {
    @Test("Every link survives a round trip")
    func roundTrip() {
        let links: [DeepLink] = [
            .compass(nearest: false), .compass(nearest: true),
            .fountain("1234567"), .route("42"), .routeToNearest,
        ]
        for link in links {
            #expect(DeepLink(url: link.url) == link)
        }
    }

    @Test("The grammar is exactly toret://<screen>[/<argument>]")
    func shape() {
        #expect(DeepLink.fountain("9").url.absoluteString == "toret://fountain/9")
        #expect(DeepLink.compass(nearest: false).url.absoluteString == "toret://compass")
        #expect(DeepLink.routeToNearest.url.absoluteString == "toret://route/nearest")
    }

    @Test("Anything else is refused, not guessed at")
    func refused() throws {
        for text in [
            "https://example.com/fountain/1", "toret://", "toret://fountain",
            "toret://compass/elsewhere", "toret://settings", "toret://route",
        ] {
            #expect(DeepLink(url: try #require(URL(string: text))) == nil)
        }
    }
}

// MARK: - Where to measure from

@Suite("Fix resolution")
struct FixResolverTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let castello = CLLocationCoordinate2D(latitude: 45.0709, longitude: 7.6858)
    private let saoPaulo = CLLocationCoordinate2D(latitude: -23.55, longitude: -46.63)

    @Test("A fresh fix of the widget's own wins")
    func ownWins() {
        let result = FixResolver.resolve(
            own: MeasuredFix(coordinate: castello, timestamp: now.addingTimeInterval(-60)),
            bridged: Catalogue.anchor, now: now
        )
        #expect(result.provenance == .live)
        #expect(result.origin.latitude == castello.latitude)
    }

    @Test("Precise Location off is reported, not hidden")
    func approximate() {
        let result = FixResolver.resolve(
            own: MeasuredFix(coordinate: castello, timestamp: now, isApproximate: true),
            bridged: nil, now: now
        )
        #expect(result.provenance == .approximate)
        #expect(result.provenance.isMeasuringFromUser)
    }

    /// A widget reading "84 m" from a walk taken yesterday is worse than one that
    /// admits it is showing the city centre.
    @Test("A stale fix of its own gives way to the app's")
    func staleOwn() {
        let result = FixResolver.resolve(
            own: MeasuredFix(
                coordinate: saoPaulo,
                timestamp: now.addingTimeInterval(-WidgetBridge.freshness - 60)
            ),
            bridged: castello, now: now
        )
        #expect(result.provenance == .live)
        #expect(result.origin.latitude == castello.latitude)
    }

    @Test("The app's published fix stands in when the widget has none")
    func bridged() {
        let result = FixResolver.resolve(own: nil, bridged: castello, now: now)
        #expect(result.provenance == .live)
    }

    @Test("No fix at all falls back to the old town, and says why")
    func noFix() {
        let asked = FixResolver.resolve(own: nil, bridged: nil, now: now)
        #expect(asked.provenance == .centre(denied: false))
        #expect(asked.origin.latitude == Catalogue.anchor.latitude)
        #expect(!asked.provenance.isMeasuringFromUser)

        let refused = FixResolver.resolve(own: nil, bridged: nil, denied: true, now: now)
        #expect(refused.provenance == .centre(denied: true))
        #expect(refused.provenance.note?.contains("desligada") == true)
    }

    @Test("A fix far from Turin is measured from the centre and labelled")
    func outside() {
        let result = FixResolver.resolve(
            own: MeasuredFix(coordinate: saoPaulo, timestamp: now), bridged: nil, now: now
        )
        guard case let .outsideTurin(kilometres) = result.provenance else {
            Issue.record("expected outsideTurin, got \(result.provenance)")
            return
        }
        #expect(kilometres > 9_000)
        #expect(result.origin.latitude == Catalogue.anchor.latitude)
        #expect(result.provenance.eyebrow(for: .nearest) == "Longe de Turim")
    }
}

// MARK: - What the widget shows

@Suite("Widget reading")
struct WidgetReadingTests {
    private let live = FixResolver.Resolution(origin: Catalogue.anchor, provenance: .live)

    @Test("Nearest first, a handful, never a thousand")
    func nearest() {
        let reading = WidgetReading.make(source: .nearest, saved: [], resolution: live)
        #expect(reading.candidates.count == WidgetReading.listLength)
        #expect(reading.candidates == reading.candidates.sorted { $0.distance < $1.distance })
        #expect(reading.featured == reading.candidates.first)
        #expect(!reading.savedIsEmpty)
    }

    @Test("A fountain reported dry is not the one to walk to")
    func dryIsSkipped() throws {
        let plain = WidgetReading.make(source: .nearest, saved: [], resolution: live)
        let dryID = try #require(plain.candidates.first?.id)
        let reading = WidgetReading.make(
            source: .nearest, saved: [], resolution: live,
            community: [dryID: CommunitySummary(
                state: .dry, latestDate: .now, average: nil, ratingCount: 0, reportCount: 1
            )]
        )
        #expect(!reading.candidates.contains { $0.id == dryID })
    }

    @Test("Saved mode follows only the saved ones")
    func saved() throws {
        let plain = WidgetReading.make(source: .nearest, saved: [], resolution: live)
        let wanted = Set(plain.candidates.suffix(2).map(\.id))
        let reading = WidgetReading.make(source: .saved, saved: wanted, resolution: live)
        #expect(Set(reading.candidates.map(\.id)) == wanted)
        #expect(reading.eyebrow == "Sua salva mais próxima")
    }

    @Test("Nothing saved is an empty state, not the nearest fountain in disguise")
    func savedEmpty() {
        let reading = WidgetReading.make(source: .saved, saved: [], resolution: live)
        #expect(reading.savedIsEmpty)
        #expect(reading.featured == nil)
        #expect(SpokenAnswer.nearest(reading) == "Você ainda não salvou nenhuma fonte.")
    }

    @Test("The cycle button steps through the nearest three and wraps")
    func cycling() {
        let now = Date.now
        var cycle = CycleState.initial
        var featured: [String] = []
        for _ in 0 ..< 4 {
            featured.append(
                WidgetReading.make(
                    source: .nearest, saved: [], resolution: live, cycle: cycle, now: now
                ).featured?.id ?? ""
            )
            cycle = cycle.advanced(count: WidgetReading.cycleLength, now: now)
        }
        #expect(featured[0] == featured[3])
        #expect(Set(featured).count == 3)
    }
}

@Suite("Cycle state")
struct CycleStateTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("A tapped choice expires")
    func expiry() {
        let tapped = CycleState(index: 2, date: now)
        #expect(tapped.resolved(count: 3, now: now.addingTimeInterval(60)) == 2)
        #expect(tapped.resolved(count: 3, now: now.addingTimeInterval(CycleState.lifetime + 1)) == 0)
    }

    @Test("An index never points past the list")
    func clamped() {
        #expect(CycleState(index: 5, date: now).resolved(count: 3, now: now) == 2)
        #expect(CycleState(index: 1, date: now).resolved(count: 0, now: now) == 0)
        #expect(CycleState.initial.advanced(count: 0, now: now) == .initial)
    }

    @Test("Advancing from an expired choice starts over at the second")
    func advanceAfterExpiry() {
        let old = CycleState(index: 2, date: now)
        let later = now.addingTimeInterval(CycleState.lifetime + 5)
        #expect(old.advanced(count: 3, now: later).index == 1)
    }

    @Test("The store round-trips and tolerates being empty")
    func store() {
        let suite = "br.tec.nuance.toret.tests.cycle"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let defaults = UserDefaults(suiteName: suite)!
        #expect(CycleStore.load(from: defaults) == .initial)

        let state = CycleStore.advance(count: 3, defaults: defaults, now: now)
        #expect(state.index == 1)
        let again = CycleStore.advance(count: 3, defaults: defaults, now: now.addingTimeInterval(5))
        #expect(again.index == 2)
        #expect(CycleStore.load(from: defaults) == again)
    }
}

// MARK: - Saying it

@Suite("Wording")
struct WordingTests {
    @Test("The eight winds, on the right side of every boundary")
    func cardinals() {
        #expect(Bearing.cardinal(0) == "N")
        #expect(Bearing.cardinal(22.4) == "N")
        #expect(Bearing.cardinal(22.6) == "NE")
        #expect(Bearing.cardinal(90) == "L")
        #expect(Bearing.cardinal(180) == "S")
        #expect(Bearing.cardinal(270) == "O")
        #expect(Bearing.cardinal(315) == "NO")
        #expect(Bearing.cardinal(359) == "N")
        #expect(Bearing.cardinal(-10) == "N")
        #expect(Bearing.cardinal(725) == "N")
        #expect(Bearing.spokenCardinal(315) == "noroeste")
    }

    @Test("Distances switch to kilometres at a thousand")
    func distances() {
        #expect(DistanceFormat.parts(84) == ("84", "m"))
        #expect(DistanceFormat.parts(999) == ("999", "m"))
        #expect(DistanceFormat.parts(1240) == ("1,2", "km"))
        #expect(DistanceFormat.spoken(1) == "1 metro")
        #expect(DistanceFormat.spoken(84) == "84 metros")
        #expect(DistanceFormat.spoken(1500) == "1,5 quilômetros")
        #expect(DistanceFormat.short(84) == "84 m")
    }

    @Test("Refresh is quick where it can change and slow where it cannot")
    func refresh() {
        #expect(RefreshPolicy.interval(for: .live) == 600)
        #expect(RefreshPolicy.interval(for: .centre(denied: true)) > RefreshPolicy.interval(for: .live))
        #expect(RefreshPolicy.interval(for: .outsideTurin(kilometres: 9000)) == 3600)
    }

    private func reading(
        _ provenance: FixProvenance, community: [String: CommunitySummary] = [:]
    ) -> WidgetReading {
        WidgetReading.make(
            source: .nearest, saved: [],
            resolution: .init(origin: Catalogue.anchor, provenance: provenance),
            community: community
        )
    }

    @Test("The answer gives the place, the distance, the way and the walk")
    func answer() throws {
        let live = reading(.live)
        let fountain = try #require(live.featured)
        let text = SpokenAnswer.nearest(live)
        #expect(text.contains(fountain.place))
        #expect(text.contains(DistanceFormat.spoken(fountain.distance)))
        #expect(text.contains(Bearing.spokenCardinal(fountain.bearing)))
        #expect(text.contains("a pé"))
    }

    /// The app has no feed. Saying "água corrente" with nobody having said it is
    /// the one lie this app must never tell.
    @Test("Nothing is claimed about the water unless a person reported it")
    func noInventedWater() throws {
        let unknown = SpokenAnswer.nearest(reading(.live))
        #expect(!unknown.lowercased().contains("corrente"))
        #expect(!unknown.contains("Relato"))

        let id = try #require(reading(.live).featured?.id)
        let reported = SpokenAnswer.nearest(reading(.live, community: [id: CommunitySummary(
            state: .running, latestDate: .now, average: 5, ratingCount: 1, reportCount: 1
        )]))
        #expect(reported.contains("Relato recente da comunidade: água corrente."))
    }

    @Test("A measurement from somewhere else says so")
    func provenanceSpoken() {
        #expect(SpokenAnswer.nearest(reading(.centre(denied: true))).contains("Sem a sua localização"))
        #expect(SpokenAnswer.nearest(reading(.outsideTurin(kilometres: 9400))).contains("9400 quilômetros"))
        #expect(SpokenAnswer.nearest(reading(.approximate)).contains("aproximada"))
        #expect(!SpokenAnswer.nearest(reading(.live)).contains("Sem a sua localização"))
    }
}

// MARK: - The walk

@Suite("Walk progress")
struct WalkProgressTests {
    private typealias State = WalkActivityAttributes.ContentState

    private func state(
        remaining: Int = 200, heading: Double? = nil, bearing: Double = 90,
        instruction: String = "Siga em frente", arrived: Bool = false
    ) -> State {
        State(
            remaining: remaining, toNextTurn: 50, instruction: instruction, minutes: 3,
            bearing: bearing, heading: heading, arrived: arrived
        )
    }

    @Test("Arrival is twenty metres, and only on a fix worth trusting")
    func arrival() {
        #expect(WalkProgress.hasArrived(straightLine: 12, accuracy: 8))
        #expect(WalkProgress.hasArrived(straightLine: 20, accuracy: nil))
        #expect(!WalkProgress.hasArrived(straightLine: 35, accuracy: 8))
        // A fix good to 120 m cannot say you are at the fountain.
        #expect(!WalkProgress.hasArrived(straightLine: 5, accuracy: 120))
        #expect(!WalkProgress.hasArrived(straightLine: 5, accuracy: -1))
    }

    @Test("Metres left follow the route, never undercut the straight line")
    func remaining() {
        #expect(WalkProgress.remaining(routeRemaining: nil, walkedSinceRoute: 0, straightLine: 84.4) == 84)
        #expect(WalkProgress.remaining(routeRemaining: 300, walkedSinceRoute: 40, straightLine: 150) == 260)
        #expect(WalkProgress.remaining(routeRemaining: 300, walkedSinceRoute: 280, straightLine: 150) == 150)
        #expect(WalkProgress.minutes(forRemaining: 0) == 1)
        #expect(WalkProgress.minutes(forRemaining: 400) == 5)
    }

    @Test("The needle turns with the phone only when the heading is known")
    func needle() {
        #expect(state(heading: nil, bearing: 90).needleAngle == 90)
        #expect(!state(heading: nil).isRelative)
        #expect(state(heading: 90, bearing: 90).needleAngle == 0)
        #expect(state(heading: 350, bearing: 10).isRelative)
    }

    @Test("Updates are spent on news, not on jitter")
    func throttling() {
        let base = state()
        let now = Date.now
        #expect(WalkProgress.isWorthPublishing(previous: nil, next: base, lastUpdate: nil, now: now))
        #expect(!WalkProgress.isWorthPublishing(previous: base, next: base, lastUpdate: nil, now: now))
        // Two metres and two degrees: nobody can see it.
        #expect(!WalkProgress.isWorthPublishing(
            previous: base, next: state(remaining: 198, bearing: 92), lastUpdate: nil, now: now
        ))
        #expect(WalkProgress.isWorthPublishing(
            previous: base, next: state(remaining: 190), lastUpdate: nil, now: now
        ))
        #expect(WalkProgress.isWorthPublishing(
            previous: base, next: state(bearing: 140), lastUpdate: nil, now: now
        ))
        #expect(WalkProgress.isWorthPublishing(
            previous: base, next: state(instruction: "Vire à direita"), lastUpdate: nil, now: now
        ))
        // Never twice in two seconds…
        #expect(!WalkProgress.isWorthPublishing(
            previous: base, next: state(remaining: 100), lastUpdate: now, now: now.addingTimeInterval(1)
        ))
        // …except to say you have arrived.
        #expect(WalkProgress.isWorthPublishing(
            previous: base, next: state(remaining: 0, arrived: true), lastUpdate: now,
            now: now.addingTimeInterval(1)
        ))
    }
}

// MARK: - Background

@Suite("Background location")
struct BackgroundLocationTests {
    /// The setting is a promise: with the switch off nothing is watched, whatever
    /// the system permission says.
    @Test("Only 'sempre' with the switch on is monitored")
    func shouldMonitor() {
        #expect(BackgroundLocation.shouldMonitor(compassAlwaysVisible: true, authorization: .authorizedAlways))
        #expect(!BackgroundLocation.shouldMonitor(compassAlwaysVisible: false, authorization: .authorizedAlways))
        #expect(!BackgroundLocation.shouldMonitor(compassAlwaysVisible: true, authorization: .authorizedWhenInUse))
        #expect(!BackgroundLocation.shouldMonitor(compassAlwaysVisible: true, authorization: .denied))
        #expect(!BackgroundLocation.shouldMonitor(compassAlwaysVisible: true, authorization: .notDetermined))
    }

    /// A Personal-Team install has no app group: the suite is created but never
    /// shared, so the widget sees nothing the app wrote. That has to read as
    /// "no fix, nothing saved", not as a crash or a stale position.
    @Test("An unshared container reads as empty")
    func unsharedContainer() {
        let suite = "br.tec.nuance.toret.tests.unshared"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let empty = UserDefaults(suiteName: suite)!
        #expect(WidgetBridge.origin(from: empty) == nil)
        #expect(WidgetBridge.savedIDs(from: empty).isEmpty)
        let resolution = FixResolver.resolve(own: nil, bridged: WidgetBridge.origin(from: empty))
        #expect(resolution.provenance == .centre(denied: false))
    }
}
