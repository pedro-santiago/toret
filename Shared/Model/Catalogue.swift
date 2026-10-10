import CoreLocation
import Foundation

/// One row of `fountains.json`, as `tools/build-catalogue.py` writes it.
struct CatalogueEntry: Decodable, Sendable {
    let id: String
    let lat: Double
    let lon: Double
    let kind: FountainKind
    let name: String?
    let street: String?
    let zone: String?
    let ref: String?
    let wheelchair: WheelchairAccess?
    let bottle: Bool?
    let dog: Bool?
    let seasonal: Bool?
    let checked: String?
}

/// Every public drinking fountain in the Turin municipality that OpenStreetMap
/// knows about, bundled with the app so nothing here needs a network.
///
/// The positions are real; what is *not* here is the state of the water, because
/// nobody publishes it. That comes from the people who walk up to the fountain —
/// see ``CommunitySummary``.
///
/// Data (c) OpenStreetMap contributors, ODbL — https://www.openstreetmap.org/copyright
enum Catalogue {
    /// Where the design stands you: a few dozen metres east of Piazza San Carlo,
    /// the centre of the old town. It is where distances are measured from when
    /// there is no usable fix.
    static let anchor = CLLocationCoordinate2D(latitude: 45.06687, longitude: 7.68316)

    /// How far from the anchor the catalogue stays useful.
    ///
    /// Beyond this, "the nearest fountain" is a figure in hundreds of kilometres,
    /// so a fix outside Turin is reported as such rather than measured from.
    static let radius: CLLocationDistance = 30_000

    static let attribution = "© OpenStreetMap contributors (ODbL)"

    /// Decoded once per process. A missing or corrupt file leaves the app empty
    /// rather than crashing it, and ``loadFailed`` says why the list is empty.
    static let entries: [CatalogueEntry] = {
        guard let url = Bundle.main.url(forResource: "fountains", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([CatalogueEntry].self, from: data)
        else { return [] }
        return decoded
    }()

    static var loadFailed: Bool { entries.isEmpty }

    /// Every fountain, measured from `origin`, with whatever the community has said.
    static func fountains(
        from origin: CLLocationCoordinate2D = anchor,
        community: [String: CommunitySummary] = [:]
    ) -> [Fountain] {
        entries.map {
            Fountain(entry: $0, community: community[$0.id] ?? .empty, from: origin)
        }
    }

    /// True when `coordinate` is close enough to Turin for the catalogue to answer.
    static func covers(_ coordinate: CLLocationCoordinate2D) -> Bool {
        distanceToCentre(from: coordinate) <= radius
    }

    static func distanceToCentre(from coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: anchor.latitude, longitude: anchor.longitude))
    }
}
