import CoreLocation
import Foundation

// MARK: - Where the fix came from

/// Why the distances on a widget are what they are.
///
/// A widget cannot ask the user anything, and it is read in a glance. So every
/// figure it shows has to carry, in the eyebrow above it, the honest answer to
/// "measured from where?" — a distance quietly measured from the old town is a
/// plausible, wrong number on the one thing the widget is for.
enum FixProvenance: Equatable, Sendable {
    /// Measured from the user's own fix.
    case live
    /// A real fix, but Precise Location is off.
    case approximate
    /// No usable fix: measured from the centre of the old town.
    case centre(denied: Bool)
    /// A real fix, far from the catalogue.
    case outsideTurin(kilometres: Int)

    var isMeasuringFromUser: Bool {
        switch self {
        case .live, .approximate: true
        case .centre, .outsideTurin: false
        }
    }

    /// The small capitals above the figure.
    func eyebrow(for source: FountainSource) -> String {
        switch self {
        case .live:
            source == .saved
                ? String(localized: "MINHA SALVA MAIS PRÓXIMA") : String(localized: "FONTE MAIS PRÓXIMA")
        case .approximate:
            String(localized: "FONTE MAIS PRÓXIMA · APROX.")
        case .centre:
            String(localized: "NO CENTRO DE TORINO")
        case .outsideTurin:
            String(localized: "LONGE DE TURIM")
        }
    }

    /// The sentence for the widgets with room for one.
    var note: String? {
        switch self {
        case .live: nil
        case .approximate:
            String(localized: "Posição aproximada. Ative a localização precisa para medir melhor.")
        case let .centre(denied):
            denied
                ? String(localized: "Localização desligada. Distâncias a partir da Piazza San Carlo.")
                : String(localized: "Abra o Toret uma vez para medir a partir de onde você está.")
        case let .outsideTurin(kilometres):
            String(localized: "Você está a \(kilometres) km de Turim. Distâncias a partir da Piazza San Carlo.")
        }
    }
}

/// A position the widget or an intent measured, with the age that decides
/// whether it is still believable.
struct MeasuredFix: Equatable, Sendable {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    let timestamp: Date
    let isApproximate: Bool

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(coordinate: CLLocationCoordinate2D, timestamp: Date, isApproximate: Bool = false) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        self.timestamp = timestamp
        self.isApproximate = isApproximate
    }
}

/// Chooses where to measure from, in the order of how much each source can be
/// trusted: the position the widget just measured, then the one the app last
/// published, then the centre of the old town — each discarded when stale.
enum FixResolver {
    struct Resolution: Equatable, Sendable {
        let origin: CLLocationCoordinate2D
        let provenance: FixProvenance

        static func == (lhs: Resolution, rhs: Resolution) -> Bool {
            lhs.origin.latitude == rhs.origin.latitude
                && lhs.origin.longitude == rhs.origin.longitude
                && lhs.provenance == rhs.provenance
        }
    }

    /// - Parameters:
    ///   - own: what this process measured itself (the widget's location, or the
    ///     intent's one-shot request).
    ///   - bridged: what the app last published to the shared container, already
    ///     freshness-checked by ``WidgetBridge``.
    ///   - denied: whether the user has said no to location, so the widget can
    ///     say so instead of asking again.
    static func resolve(
        own: MeasuredFix?,
        bridged: CLLocationCoordinate2D?,
        denied: Bool = false,
        now: Date = .now
    ) -> Resolution {
        if let own, now.timeIntervalSince(own.timestamp) <= WidgetBridge.freshness {
            return resolution(for: own.coordinate, approximate: own.isApproximate)
        }
        if let bridged {
            return resolution(for: bridged, approximate: false)
        }
        return Resolution(origin: Catalogue.anchor, provenance: .centre(denied: denied))
    }

    private static func resolution(
        for coordinate: CLLocationCoordinate2D, approximate: Bool
    ) -> Resolution {
        guard Catalogue.covers(coordinate) else {
            let kilometres = Int((Catalogue.distanceToCentre(from: coordinate) / 1000).rounded())
            return Resolution(
                origin: Catalogue.anchor, provenance: .outsideTurin(kilometres: kilometres)
            )
        }
        return Resolution(origin: coordinate, provenance: approximate ? .approximate : .live)
    }
}

// MARK: - What to show

/// The two things a widget can be told to follow.
enum FountainSource: String, Sendable, CaseIterable {
    case nearest
    case saved
}

/// Steps through the nearest few when the user taps the widget's button.
///
/// A choice made a quarter of an hour ago, from somewhere else, is not a choice
/// anymore: it expires, so the widget goes back to the nearest fountain rather
/// than insisting on the third-nearest one from yesterday's walk.
struct CycleState: Equatable, Sendable {
    /// How long a tapped choice is honoured.
    static let lifetime: TimeInterval = 10 * 60

    var index: Int
    var date: Date

    static let initial = CycleState(index: 0, date: .distantPast)

    /// The index to show, given how many candidates there are.
    func resolved(count: Int, now: Date = .now) -> Int {
        guard count > 0, now.timeIntervalSince(date) <= Self.lifetime else { return 0 }
        return index % count
    }

    /// The state after one more tap.
    func advanced(count: Int, now: Date = .now) -> CycleState {
        guard count > 0 else { return .initial }
        return CycleState(index: (resolved(count: count, now: now) + 1) % count, date: now)
    }
}

/// Everything a widget, a control or a spoken answer needs, worked out once.
struct WidgetReading: Sendable {
    /// How many fountains a large widget lists.
    static let listLength = 4
    /// How many the cycle button steps through.
    static let cycleLength = 3

    let source: FountainSource
    let provenance: FixProvenance
    let origin: CLLocationCoordinate2D
    /// Nearest first, never reported dry, at most ``listLength``.
    let candidates: [Fountain]
    /// The one the big figure is about, after the cycle button.
    let featured: Fountain?
    /// True when the widget was asked for the saved ones and there are none.
    let savedIsEmpty: Bool

    var eyebrow: String { provenance.eyebrow(for: source) }

    /// The rest of the list under the featured fountain.
    var others: [Fountain] {
        guard let featured else { return [] }
        return candidates.filter { $0 != featured }
    }

    /// How many fountains the cycle button steps through.
    var cycleCount: Int { min(Self.cycleLength, candidates.count) }

    static func make(
        source: FountainSource,
        saved: Set<String>,
        resolution: FixResolver.Resolution,
        cycle: CycleState = .initial,
        now: Date = .now
    ) -> WidgetReading {
        let everything = Catalogue.fountains(from: resolution.origin)
        let pool = source == .saved ? everything.filter { saved.contains($0.id) } : everything
        let ranked = pool
            .filter { $0.state.isUsable }
            .sorted { $0.distance < $1.distance }
        let candidates = Array(ranked.prefix(listLength))
        let count = min(cycleLength, candidates.count)
        let featured = candidates.isEmpty ? nil : candidates[cycle.resolved(count: count, now: now)]
        return WidgetReading(
            source: source,
            provenance: resolution.provenance,
            origin: resolution.origin,
            candidates: candidates,
            featured: featured,
            savedIsEmpty: source == .saved && saved.isEmpty
        )
    }

    /// The gallery and placeholder reading: the nearest water to the old town.
    static var preview: WidgetReading {
        make(
            source: .nearest, saved: [],
            resolution: .init(origin: Catalogue.anchor, provenance: .live)
        )
    }
}

// MARK: - Saying it

extension Bearing {
    /// The eight winds, in Portuguese: N, NE, L, SE, S, SO, O, NO.
    ///
    /// A widget cannot know which way the phone faces, so it names the direction
    /// the way a map would — which is also what the compass screen prints on its
    /// own dial (N, L, S, O).
    static func cardinal(_ degrees: Double) -> String {
        let names = ["N", "NE", "L", "SE", "S", "SO", "O", "NO"]
        let normalised = (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        return names[Int((normalised + 22.5) / 45) % 8]
    }
}

/// A distance as a figure and a unit: 84 → "84" "m", 1240 → "1,2" "km".
enum DistanceFormat {
    static func parts(_ metres: Int) -> (value: String, unit: String) {
        guard metres >= 1000 else { return (String(metres), "m") }
        let kilometres = (Double(metres) / 1000).formatted(
            .number.precision(.fractionLength(1)).locale(Locale(identifier: "pt_BR"))
        )
        return (kilometres, "km")
    }

    static func spoken(_ metres: Int) -> String {
        guard metres >= 1000 else {
            return metres == 1 ? "1 metro" : "\(metres) metros"
        }
        return parts(metres).value + " quilômetros"
    }

    static func short(_ metres: Int) -> String {
        let parts = parts(metres)
        return "\(parts.value) \(parts.unit)"
    }
}

extension Fountain {
    /// The line under a fountain's name where a widget has room for one.
    ///
    /// What the community said, if anyone has said anything recently — and the
    /// kind and neighbourhood otherwise. Never a claim the data cannot back.
    var widgetCaption: String {
        state == .unknown ? "\(kind.label) · \(zone)" : "\(state.label) · \(kind.label)"
    }

    /// "a NO" — the direction, for widgets that cannot turn with the phone.
    var cardinalPhrase: String { String(localized: "a \(Bearing.cardinal(bearing))") }

    var deepLink: URL { DeepLink.fountain(id).url }
}

extension WidgetReading {
    /// "Olhe para os Alpes" when a landmark sits within 15° of the bearing to the
    /// featured fountain, and nothing otherwise — a hint, not a promise.
    var lookHint: String? {
        guard let featured else { return nil }
        let match = Landmark.ring(from: origin)
            .map { ($0, Bearing.separation($0.bearing, featured.bearing)) }
            .min { $0.1 < $1.1 }
        guard let match, match.1 < 15 else { return nil }
        return String(localized: "Olhe para \(match.0.spoken)")
    }
}
