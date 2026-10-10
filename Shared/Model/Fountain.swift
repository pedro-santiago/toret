import CoreLocation
import SwiftUI

/// What the community says about the water at a fountain.
///
/// The app has no feed of its own and does not pretend to: a fountain is
/// `.unknown` until someone standing at it says otherwise, and a report goes
/// stale after ``CommunitySummary/freshness``. The design gives each state exactly
/// one colour and never reuses it, so the colour is a property of the state rather
/// than a decision made at each call site. `nightColor` is the same meaning
/// re-tinted for the dark screens.
enum WaterState: String, Codable, Sendable, CaseIterable {
    case running
    case weak
    case dry
    /// Nobody has reported on it recently. The honest default.
    case unknown

    var label: String {
        switch self {
        case .running: String(localized: "Água corrente")
        case .weak: String(localized: "Fluxo fraco")
        case .dry: String(localized: "Sem água")
        case .unknown: String(localized: "Sem relato recente")
        }
    }

    /// Short form for tight places: pins, chips, the widget.
    var shortLabel: String {
        switch self {
        case .running: String(localized: "Corrente")
        case .weak: String(localized: "Fraca")
        case .dry: String(localized: "Seca")
        case .unknown: String(localized: "Sem relato")
        }
    }

    /// The three states a person can report. `.unknown` is the absence of one.
    static let reportable: [WaterState] = [.running, .weak, .dry]

    /// Dry is the only state worth steering someone away from; an unreported
    /// fountain is still the best guess within reach.
    var isUsable: Bool { self != .dry }

    var color: Color {
        switch self {
        case .running: Palette.green
        case .weak: Palette.ocre
        case .dry: Palette.terracotta
        case .unknown: Palette.stone
        }
    }

    /// The night-legible counterpart, for the compass and lock screens.
    var nightColor: Color {
        switch self {
        case .running: Palette.sage
        case .weak: Palette.sand
        case .dry: Palette.clay
        case .unknown: Palette.stoneNight
        }
    }

    /// Colour appropriate to the surface the pin is drawn on.
    func color(night: Bool) -> Color { night ? nightColor : color }
}

/// Which pattern of public drinking fountain it is, as OpenStreetMap tags it.
enum FountainKind: String, Codable, Sendable {
    /// The cast-iron bull's-head column the app is named after.
    case toret
    /// Any other public drinking fountain.
    case fountain
    /// A bubbler: a jet you drink from directly.
    case bubbler
    /// A tap built to fill a bottle.
    case refill

    var label: String {
        switch self {
        case .toret: String(localized: "Toret")
        case .fountain: String(localized: "Fonte pública")
        case .bubbler: String(localized: "Bebedouro")
        case .refill: String(localized: "Recarga de garrafa")
        }
    }
}

/// Whether a wheelchair can reach the bowl, as OpenStreetMap contributors tagged it.
enum WheelchairAccess: String, Codable, Sendable {
    case yes, limited, no

    var label: String {
        switch self {
        case .yes: String(localized: "Acessível")
        case .limited: String(localized: "Acesso parcial")
        case .no: String(localized: "Sem acesso")
        }
    }
}

/// A *toret* — or any other public drinking fountain in Turin.
///
/// The interface calls them all "fontes"; only the app is named after the bull.
///
/// `distance` and `bearing` are stored rather than computed because every screen
/// reads them dozens of times a frame, and they only change when you move. See
/// ``relocated(to:)`` — the model re-derives the whole list on each location fix.
///
/// Identity is the OpenStreetMap node id and nothing else: two values for the same
/// fountain measured from different places, or with different community state,
/// are the same fountain.
struct Fountain: Identifiable, Sendable {
    /// OpenStreetMap node id.
    let id: String
    let kind: FountainKind
    let name: String?
    let street: String?
    let neighbourhood: String?
    /// The operator's plate number, where OpenStreetMap carries one.
    let ref: String?
    let wheelchair: WheelchairAccess?
    let hasBottleFiller: Bool
    let allowsDogs: Bool
    /// Switched off in winter, so a missing flow between November and March is
    /// not a fault.
    let isSeasonal: Bool
    /// When a mapper last confirmed the point, as OpenStreetMap writes it.
    let checked: String?
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees

    /// What the community last said, and how many people have rated it.
    var community: CommunitySummary

    /// Metres from the user, over the ground.
    let distance: Int
    /// Compass bearing from the user to the fountain, degrees clockwise from north.
    let bearing: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var state: WaterState { community.state }

    init(
        entry: CatalogueEntry,
        community: CommunitySummary = .empty,
        from origin: CLLocationCoordinate2D
    ) {
        id = entry.id
        kind = entry.kind
        name = entry.name
        street = entry.street
        neighbourhood = entry.zone
        ref = entry.ref
        wheelchair = entry.wheelchair
        hasBottleFiller = entry.bottle ?? false
        allowsDogs = entry.dog ?? false
        isSeasonal = entry.seasonal ?? false
        checked = entry.checked
        latitude = entry.lat
        longitude = entry.lon
        self.community = community

        let here = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let there = CLLocation(latitude: entry.lat, longitude: entry.lon)
        distance = Int(here.distance(from: there).rounded())
        bearing = Bearing.forwardAzimuth(from: origin, to: there.coordinate)
    }

    private init(copying other: Fountain, community: CommunitySummary, distance: Int, bearing: Double) {
        id = other.id
        kind = other.kind
        name = other.name
        street = other.street
        neighbourhood = other.neighbourhood
        ref = other.ref
        wheelchair = other.wheelchair
        hasBottleFiller = other.hasBottleFiller
        allowsDogs = other.allowsDogs
        isSeasonal = other.isSeasonal
        checked = other.checked
        latitude = other.latitude
        longitude = other.longitude
        self.community = community
        self.distance = distance
        self.bearing = bearing
    }

    /// The same fountain, measured from somewhere else.
    func relocated(to origin: CLLocationCoordinate2D) -> Fountain {
        let here = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let there = CLLocation(latitude: latitude, longitude: longitude)
        return Fountain(
            copying: self, community: community,
            distance: Int(here.distance(from: there).rounded()),
            bearing: Bearing.forwardAzimuth(from: origin, to: there.coordinate)
        )
    }

    /// The same fountain, with what the community has since said about it.
    func with(community: CommunitySummary) -> Fountain {
        Fountain(copying: self, community: community, distance: distance, bearing: bearing)
    }

    /// Walking minutes, on the design's 80 m/min pace, never rounded to zero.
    var walkingMinutes: Int { max(1, Int((Double(distance) / 80).rounded())) }

    /// Names OpenStreetMap mappers use when they have nothing to say, in the
    /// languages they write them in: Italian first, then English and Portuguese.
    /// Compared lowercased and without accents, so "Água potável" and
    /// "agua potavel" are the same name. These are data, not interface text, so
    /// they stay out of the string catalog.
    private static let genericNames: Set<String> = [
        "toret", "toretto", "fontanella", "fontanelle", "fontanella pubblica", "fontana",
        "fontana pubblica", "acqua", "acqua potabile", "acqua pubblica", "idrante",
        "drinking water", "drinking fountain", "water", "water fountain", "fountain",
        "public fountain", "bubbler", "water tap", "tap",
        "fonte", "fonte publica", "bebedouro", "agua", "agua potavel", "torneira",
    ]

    private static func isGeneric(_ name: String) -> Bool {
        genericNames.contains(
            name.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        )
    }

    /// What the fountain is called: its own name if it has a real one, otherwise
    /// the street it stands on, otherwise the neighbourhood.
    var place: String {
        if let name, !Self.isGeneric(name) { return name }
        return street ?? neighbourhood.map { "\(kind.label) · \($0)" } ?? kind.label
    }

    /// A second line under the title: the street when the title is a name, the
    /// neighbourhood when the title is the street.
    var addressLine: String? {
        if let name, place == name, let street { return street }
        return neighbourhood
    }

    /// ``place``, with just enough added to tell it from another fountain in `group`
    /// that goes by the same name — Turin has more than one on Piazza San Carlo,
    /// and a list that shows the same words twice looks like a bug. The plate
    /// number first, then the neighbourhood, then which way it lies from you.
    func place(distinguishedIn group: [Fountain]) -> String {
        guard let extra = distinguisher(in: group) else { return place }
        return "\(place) · \(extra)"
    }

    /// What tells this fountain from another in `group` with the same name, or nil
    /// when nothing needs telling. Short enough for a subtitle: "n. 70060",
    /// "Aurora", "NO".
    func distinguisher(in group: [Fountain]) -> String? {
        let rivals = group.filter { $0.id != id && $0.place == place }
        guard !rivals.isEmpty else { return nil }
        if let ref, rivals.allSatisfy({ $0.ref != ref }) {
            return String(localized: "n. \(ref)")
        }
        if !place.contains(zone), rivals.allSatisfy({ $0.zone != zone }) {
            return zone
        }
        return Bearing.cardinal(bearing)
    }

    /// The neighbourhood, never empty.
    var zone: String { neighbourhood ?? String(localized: "Turim") }

    /// "Toret n. 69442" where there is a plate, "Toret" where there is not.
    var plateTitle: String {
        ref.map { String(localized: "\(kind.label) n. \($0)") } ?? kind.label
    }

    /// The place name broken for display type: "Corso / Vittorio Emanuele II".
    ///
    /// Turin names its squares and streets with a generic first — piazza, via,
    /// corso — which makes the break after the first word the right one at 38 pt.
    var titleLines: String {
        let words = place.split(separator: " ")
        guard words.count > 1 else { return place }
        return words[0] + "\n" + words.dropFirst().joined(separator: " ")
    }

    /// Everything the search field matches against, lowercased and unaccented.
    var searchHaystack: String {
        [place, street, neighbourhood, kind.label, ref]
            .compactMap { $0 }
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}

extension Fountain: Hashable {
    static func == (lhs: Fountain, rhs: Fountain) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
