import CoreLocation
import MapKit
import Testing

@testable import Toret

private func fountain(
    _ id: String, lat: Double, lon: Double, state: WaterState = .unknown
) -> Fountain {
    let entry = CatalogueEntry(
        id: id, lat: lat, lon: lon, kind: .fountain, name: nil, street: "Via Test",
        zone: "Centro", ref: nil, wheelchair: nil, bottle: nil, dog: nil, seasonal: nil, checked: nil
    )
    let summary = CommunitySummary(
        state: state, latestDate: state == .unknown ? nil : .now,
        average: nil, ratingCount: 0, reportCount: state == .unknown ? 0 : 1
    )
    return Fountain(entry: entry, community: summary, from: Catalogue.anchor)
}

@Suite("Pin density")
struct PinDensityTests {
    @Test("The mark shrinks as the map widens")
    func levels() {
        #expect(PinDensity(latitudeSpan: 0.006) == .full)
        #expect(PinDensity(latitudeSpan: PinDensity.smallBeyond) == .full)
        #expect(PinDensity(latitudeSpan: 0.02) == .small)
        #expect(PinDensity(latitudeSpan: PinDensity.dotBeyond) == .small)
        #expect(PinDensity(latitudeSpan: 0.08) == .dot)
        #expect(PinDensity.full.markSize > PinDensity.small.markSize)
        #expect(PinDensity.small.markSize > PinDensity.dot.markSize)
    }

    /// Street level must keep a full 44 pt target; denser levels give some of it
    /// up so neighbouring pins do not steal each other's taps.
    @Test("Street-level pins keep the full hit target")
    func hitTargets() {
        #expect(PinDensity.full.hitSize >= 44)
        #expect(PinDensity.dot.hitSize < PinDensity.full.hitSize)
    }
}

@Suite("Pin layout")
struct PinLayoutTests {
    private let center = CLLocationCoordinate2D(latitude: 45.07, longitude: 7.68)

    @Test("Only what is in view, plus a margin, is drawn")
    func visibility() {
        let region = MKCoordinateRegion(
            center: center, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        let near = fountain("near", lat: 45.071, lon: 7.681)
        let edge = fountain("edge", lat: 45.07 + 0.0055, lon: 7.68)
        let far = fountain("far", lat: 45.12, lon: 7.75)
        let seen = PinLayout.visible([near, edge, far], in: region)
        #expect(seen.contains(near))
        #expect(seen.contains(edge))
        #expect(!seen.contains(far))
        #expect(PinLayout.visible([near, far], in: nil).count == 2)
    }

    @Test("Zoomed in, every fountain is its own pin")
    func noClusteringAtStreetLevel() {
        let fountains = (0 ..< 6).map { fountain("f\($0)", lat: 45.07 + Double($0) * 0.0001, lon: 7.68) }
        let items = PinLayout.items(for: fountains, latitudeSpan: 0.008, pinned: [])
        #expect(items.count == 6)
        #expect(items.allSatisfy { if case .fountain = $0 { true } else { false } })
    }

    @Test("Zoomed out, neighbours fold into a counted badge")
    func clustering() {
        let crowd = (0 ..< 5).map { fountain("c\($0)", lat: 45.07 + Double($0) * 0.0002, lon: 7.68) }
        let loner = fountain("alone", lat: 45.20, lon: 7.90)
        let items = PinLayout.items(for: crowd + [loner], latitudeSpan: 0.12, pinned: [])
        let clusters = items.compactMap { item -> PinCluster? in
            if case let .cluster(cluster) = item { cluster } else { nil }
        }
        #expect(clusters.count == 1)
        #expect(clusters.first?.count == 5)
        #expect(items.count == 2)
    }

    @Test("The selected and saved fountains are never folded away")
    func pinnedStayIndividual() {
        let crowd = (0 ..< 5).map { fountain("c\($0)", lat: 45.07 + Double($0) * 0.0002, lon: 7.68) }
        let items = PinLayout.items(for: crowd, latitudeSpan: 0.12, pinned: ["c2"])
        let singles = items.compactMap { item -> Fountain? in
            if case let .fountain(fountain) = item { fountain } else { nil }
        }
        #expect(singles.map(\.id) == ["c2"])
        let badge = items.compactMap { item -> PinCluster? in
            if case let .cluster(cluster) = item { cluster } else { nil }
        }
        #expect(badge.first?.count == 4)
    }

    @Test("Tapping a badge always ends at a street-level view")
    func zoomRegion() {
        let crowd = (0 ..< 3).map { fountain("z\($0)", lat: 45.07 + Double($0) * 0.00001, lon: 7.68) }
        let items = PinLayout.items(for: crowd, latitudeSpan: 0.12, pinned: [])
        guard case let .cluster(cluster) = items.first else {
            Issue.record("expected a cluster")
            return
        }
        #expect(cluster.zoomRegion.span.latitudeDelta >= 0.006)
        #expect(PinDensity(latitudeSpan: cluster.zoomRegion.span.latitudeDelta) != .dot)
    }

    @Test("Over the real catalogue, the whole-city view stays small")
    func realCatalogue() {
        let all = Catalogue.fountains()
        let items = PinLayout.items(for: all, latitudeSpan: 0.2, pinned: [])
        #expect(items.count < all.count / 3)
        let folded = items.reduce(0) { total, item in
            switch item {
            case .fountain: total + 1
            case let .cluster(cluster): total + cluster.count
            }
        }
        #expect(folded == all.count)
    }
}

@Suite("Map copy")
struct StateSentenceTests {
    @Test("Nobody has reported: say so in plain words")
    func unreported() {
        let lines = StateSentence.lines(for: .empty)
        #expect(lines.headline == WaterState.unknown.label)
        #expect(!lines.detail.isEmpty)
        #expect(lines.detail == lines.detail.prefix(1).uppercased() + lines.detail.dropFirst())
    }

    @Test("A fresh report is in sentence case, not capitals")
    func fresh() {
        let summary = CommunitySummary(
            state: .running, latestDate: .now.addingTimeInterval(-2 * 3600),
            average: nil, ratingCount: 0, reportCount: 1
        )
        let lines = StateSentence.lines(for: summary)
        #expect(lines.headline == WaterState.running.label)
        #expect(lines.detail.hasPrefix("Relato"))
        #expect(lines.detail != lines.detail.uppercased())
    }

    @Test("Sentence case lowers everything but the first letter")
    func sentence() {
        #expect(StateSentence.sentenceCase("RELATO HÁ 2 H") == "Relato há 2 h")
        #expect(StateSentence.sentenceCase("") == "")
    }
}

@Suite("Route framing")
@MainActor
struct RouteFramingTests {
    @Test("A very short walk is still framed wide enough to see the streets")
    func shortWalk() {
        let origin = Catalogue.anchor
        let target = CLLocationCoordinate2D(latitude: origin.latitude + 0.0001, longitude: origin.longitude)
        let rect = RouteScreen.framing(nil, from: origin, to: target)
        let metres = rect.width / MKMapPointsPerMeterAtLatitude(origin.latitude)
        #expect(metres > 160)
    }

    @Test("The framing contains both ends of the walk")
    func containsEnds() {
        let origin = Catalogue.anchor
        let target = CLLocationCoordinate2D(latitude: origin.latitude + 0.004, longitude: origin.longitude + 0.003)
        let rect = RouteScreen.framing(nil, from: origin, to: target)
        #expect(rect.contains(MKMapPoint(origin)))
        #expect(rect.contains(MKMapPoint(target)))
    }

    @Test("A fix within twenty metres counts as arriving")
    func arrival() {
        #expect(RouteScreen.arrivalRadius == 20)
    }
}
