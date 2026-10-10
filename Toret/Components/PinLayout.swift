import CoreLocation
import MapKit

/// How much of a fountain the map draws, by how far you are zoomed out.
///
/// Seven hundred full-size marks is a wall of ink, and seven hundred annotations
/// is what makes a SwiftUI map stutter. So the mark shrinks as the map widens and,
/// past a point, neighbours fold into a numbered badge you can tap to zoom into.
enum PinDensity: Equatable, Sendable {
    /// Street level: the full state mark, with room to read its shape.
    case full
    /// A neighbourhood: a small mark, still shape-coded.
    case small
    /// The whole city: a dot, and badges where dots would touch.
    case dot

    /// Latitude spans, in degrees, where each level begins. 0.012° is about a
    /// kilometre of map height; 0.03° is the width of the old town.
    static let smallBeyond = 0.012
    static let dotBeyond = 0.03

    init(latitudeSpan: Double) {
        if latitudeSpan <= Self.smallBeyond { self = .full }
        else if latitudeSpan <= Self.dotBeyond { self = .small }
        else { self = .dot }
    }

    /// Size of the mark, in points.
    var markSize: CGFloat {
        switch self {
        case .full: 22
        case .small: 14
        case .dot: 9
        }
    }

    /// The tappable square. Dense levels get a smaller one so neighbours do not
    /// steal each other's taps; street level gets the full 44 pt.
    var hitSize: CGFloat {
        switch self {
        case .full: 44
        case .small: 34
        case .dot: 26
        }
    }
}

/// Several fountains folded into one badge.
struct PinCluster: Identifiable, Equatable, Sendable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let count: Int
    /// The smallest box holding every member, for zooming into it.
    let minLatitude: Double
    let maxLatitude: Double
    let minLongitude: Double
    let maxLongitude: Double

    /// The region to fly to: the members' box with room round it, never tighter
    /// than street level, so a tap always ends with something to tap.
    var zoomRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: max(0.006, (maxLatitude - minLatitude) * 1.8),
                longitudeDelta: max(0.006, (maxLongitude - minLongitude) * 1.8)
            )
        )
    }

    static func == (lhs: PinCluster, rhs: PinCluster) -> Bool {
        lhs.id == rhs.id && lhs.count == rhs.count
    }
}

/// One thing the map draws.
enum PinItem: Identifiable {
    case fountain(Fountain)
    case cluster(PinCluster)

    var id: String {
        switch self {
        case let .fountain(fountain): "f-\(fountain.id)"
        case let .cluster(cluster): "c-\(cluster.id)"
        }
    }
}

/// Decides what is on the map for a given view of it. Pure, so it can be tested
/// without a map.
enum PinLayout {
    /// Fountains inside the view, with a margin so pins do not pop in at the
    /// edge while you pan.
    static func visible(
        _ fountains: [Fountain], in region: MKCoordinateRegion?, margin: Double = 0.6
    ) -> [Fountain] {
        guard let region else { return fountains }
        let latitudeReach = region.span.latitudeDelta * margin
        let longitudeReach = region.span.longitudeDelta * margin
        return fountains.filter {
            abs($0.latitude - region.center.latitude) <= latitudeReach
                && abs($0.longitude - region.center.longitude) <= longitudeReach
        }
    }

    /// What to draw for `fountains` at this zoom.
    ///
    /// The selected fountain and the saved ones are never folded into a badge:
    /// they are the ones you came to the map for.
    static func items(
        for fountains: [Fountain],
        latitudeSpan: Double,
        pinned: Set<String>
    ) -> [PinItem] {
        guard PinDensity(latitudeSpan: latitudeSpan) == .dot else {
            return fountains.map { .fountain($0) }
        }

        // A grid a sixth of the view wide: marks closer than that would touch.
        let cell = max(latitudeSpan / 6, 0.0005)
        var buckets: [String: [Fountain]] = [:]
        var items: [PinItem] = []
        for fountain in fountains {
            if pinned.contains(fountain.id) {
                items.append(.fountain(fountain))
                continue
            }
            let key = "\(Int((fountain.latitude / cell).rounded(.down))):\(Int((fountain.longitude / cell).rounded(.down)))"
            buckets[key, default: []].append(fountain)
        }
        for (key, members) in buckets.sorted(by: { $0.key < $1.key }) {
            guard members.count > 1 else {
                items.append(.fountain(members[0]))
                continue
            }
            let latitudes = members.map(\.latitude), longitudes = members.map(\.longitude)
            items.append(.cluster(PinCluster(
                id: key,
                coordinate: CLLocationCoordinate2D(
                    latitude: latitudes.reduce(0, +) / Double(members.count),
                    longitude: longitudes.reduce(0, +) / Double(members.count)
                ),
                count: members.count,
                minLatitude: latitudes.min() ?? 0, maxLatitude: latitudes.max() ?? 0,
                minLongitude: longitudes.min() ?? 0, maxLongitude: longitudes.max() ?? 0
            )))
        }
        return items
    }
}

/// The words the map plate uses for the state of the water, in sentence case.
///
/// `CommunitySummary.provenance` is set in capitals for the stat blocks; the
/// poster wants plain sentences, so the same facts are re-said here.
enum StateSentence {
    /// The headline ("Água corrente") and the line under it ("Relato há 2 h").
    static func lines(for summary: CommunitySummary) -> (headline: String, detail: String) {
        let detail: String
        switch (summary.state, summary.latestDate) {
        case (_, nil):
            detail = String(localized: "Ninguém relatou ainda")
        case (.unknown, _):
            detail = sentenceCase(summary.provenance)
        default:
            detail = sentenceCase(summary.provenance)
        }
        return (summary.state.label, detail)
    }

    /// "RELATO HÁ 2 H" → "Relato há 2 h".
    static func sentenceCase(_ text: String) -> String {
        let lowered = text.lowercased()
        return lowered.prefix(1).uppercased() + lowered.dropFirst()
    }
}
