import CoreLocation
import Foundation

/// A thing you can see from the street.
///
/// The compass ring is not decoration. A tourist who does not know Turin cannot
/// act on "296°", but can act on "look between the Mole and Superga" — so every
/// bearing is spoken back in terms of whichever landmarks bracket it. The
/// bearings are computed from the real positions of the buildings, against
/// wherever you are standing, so the sentence stays true as you move.
struct Landmark: Identifiable, Hashable, Sendable {
    /// How the thing is drawn — its silhouette, not a generic pin. A tourist
    /// matches the shape to the skyline rather than to a legend.
    enum Glyph: Hashable, Sendable { case lozenge, square, dome, arch, range }

    /// Which landmark it is, independent of the language it is named in. Code that
    /// has to recognise one (the Mole is drawn as its own silhouette) switches on
    /// this, never on the text.
    enum Key: String, Hashable, Sendable {
        case duomo, mole, superga, cappuccini, portaNuova, alps, portePalatine
    }

    let key: Key
    let glyph: Glyph
    /// Whether it earns a place on the compass ring.
    let onRing: Bool
    /// Whether it is close enough to be a point on the map.
    var onMap: Bool { glyph != .range }
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    /// Bearing from the current origin, degrees clockwise from north.
    let bearing: Double

    var id: String { key.rawValue }

    /// Ring label, set in narrow capitals, in the reader's language: "ALPES",
    /// "ALPS", "ALPI". Most are proper names that read the same everywhere.
    var name: String {
        switch key {
        case .duomo: String(localized: "DUOMO")
        case .mole: String(localized: "MOLE")
        case .superga: String(localized: "SUPERGA")
        case .cappuccini: String(localized: "M. CAPPUCCINI")
        case .portaNuova: String(localized: "PORTA NUOVA")
        case .alps: String(localized: "ALPES")
        case .portePalatine: String(localized: "PORTE PALATINE")
        }
    }

    /// The same landmark inside a sentence, with its article: "o Duomo", "the
    /// Duomo", "il Duomo". Each language carries its own article, so the sentence
    /// around it never has to guess a gender.
    var spoken: String {
        switch key {
        case .duomo: String(localized: "o Duomo")
        case .mole: String(localized: "a Mole Antonelliana")
        case .superga: String(localized: "a Basilica di Superga")
        case .cappuccini: String(localized: "o Monte dei Cappuccini")
        case .portaNuova: String(localized: "Porta Nuova")
        case .alps: String(localized: "os Alpes")
        case .portePalatine: String(localized: "as Porte Palatine")
        }
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private init(
        _ key: Key, _ glyph: Glyph, onRing: Bool = true,
        _ latitude: CLLocationDegrees, _ longitude: CLLocationDegrees,
        from origin: CLLocationCoordinate2D
    ) {
        self.key = key
        self.glyph = glyph
        self.onRing = onRing
        self.latitude = latitude
        self.longitude = longitude
        bearing = Bearing.forwardAzimuth(
            from: origin,
            to: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        )
    }

    /// The skyline of Turin, as seen from `origin`.
    ///
    /// Superga is eight kilometres out on its hill and the Alps are forty; both
    /// earn their place on the ring precisely because they are visible from the
    /// middle of town on a clear day.
    static func all(from origin: CLLocationCoordinate2D) -> [Landmark] {
        [
            Landmark(.duomo, .dome, 45.0733, 7.6856, from: origin),
            Landmark(.mole, .lozenge, 45.0690, 7.6934, from: origin),
            Landmark(.superga, .dome, 45.0808, 7.7684, from: origin),
            Landmark(.cappuccini, .dome, 45.0616, 7.6947, from: origin),
            Landmark(.portaNuova, .square, 45.0623, 7.6787, from: origin),
            Landmark(.alps, .range, 45.1400, 7.2200, from: origin),
            // On the map but not on the ring: it is a mark you navigate past
            // rather than a bearing you take.
            Landmark(.portePalatine, .arch, onRing: false,
                     45.0745, 7.6836, from: origin),
        ]
    }

    /// The six that ring the compass dial.
    static func ring(from origin: CLLocationCoordinate2D) -> [Landmark] {
        all(from: origin).filter(\.onRing)
    }

    /// The silhouettes drawn on the map.
    static func onMap(from origin: CLLocationCoordinate2D) -> [Landmark] {
        all(from: origin).filter(\.onMap)
    }

    /// How far out a landmark stands on the compass rim.
    enum Tier: Int, Sendable { case inner = 0, outer = 1 }

    /// Steps colliding landmarks apart on the rim.
    ///
    /// The bearings are real, and from the middle of town the Mole and Superga are
    /// only ten degrees apart. A mark that lands within `minimumSeparation` of the
    /// last one placed on its tier moves out to the other tier instead of printing
    /// over it. With two tiers the third of a tight cluster has nowhere to go and
    /// is left where it falls — at six landmarks that does not happen in Turin.
    static func tiers(
        for landmarks: [Landmark], minimumSeparation: Double = 14
    ) -> [(landmark: Landmark, tier: Tier)] {
        var lastOnTier: [Tier: Double] = [:]
        var placed: [(landmark: Landmark, tier: Tier)] = []
        for mark in landmarks.sorted(by: { $0.bearing < $1.bearing }) {
            let preferred: Tier = .inner
            let tier: Tier
            if let last = lastOnTier[preferred],
               Bearing.separation(mark.bearing, last) < minimumSeparation {
                tier = .outer
            } else {
                tier = preferred
            }
            lastOnTier[tier] = mark.bearing
            placed.append((mark, tier))
        }
        return placed
    }

    /// The landmark within `tolerance` degrees of `bearing`, if any.
    static func facing(
        _ bearing: Double, from origin: CLLocationCoordinate2D, tolerance: Double = 12
    ) -> Landmark? {
        ring(from: origin)
            .map { ($0, Bearing.separation($0.bearing, bearing)) }
            .filter { $0.1 <= tolerance }
            .min { $0.1 < $1.1 }?.0
    }

    /// Phrases a bearing as something you can do with your body.
    ///
    /// Within 15° of a landmark you are told to line up with it; otherwise you
    /// are given the two it falls between.
    static func orientation(for bearing: Double, from origin: CLLocationCoordinate2D) -> String {
        let ranked = ring(from: origin)
            .map { ($0, Bearing.separation($0.bearing, bearing)) }
            .sorted { $0.1 < $1.1 }
        guard let nearest = ranked.first else { return "" }
        if nearest.1 < 15 { return String(localized: "Alinhe-se com \(nearest.0.spoken)") }
        guard ranked.count > 1 else { return String(localized: "Alinhe-se com \(nearest.0.spoken)") }
        return String(localized: "Olhe entre \(nearest.0.spoken) e \(ranked[1].0.spoken)")
    }
}

/// Arithmetic on compass bearings.
enum Bearing {
    /// Folds any angle into 0..<360.
    static func normalized(_ degrees: Double) -> Double {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// Where something is relative to the way you face, in a sentence: "à sua
    /// esquerda", "atrás de você, à direita". `relative` is bearing minus heading.
    static func relativePhrase(_ relative: Double) -> String {
        let phrases = [
            String(localized: "à sua frente"),
            String(localized: "à sua frente, à direita"),
            String(localized: "à sua direita"),
            String(localized: "atrás de você, à direita"),
            String(localized: "atrás de você"),
            String(localized: "atrás de você, à esquerda"),
            String(localized: "à sua esquerda"),
            String(localized: "à sua frente, à esquerda"),
        ]
        return phrases[Int((normalized(relative) + 22.5) / 45) % 8]
    }

    /// Initial great-circle bearing from one coordinate to another, 0..<360°
    /// clockwise from true north.
    static func forwardAzimuth(
        from origin: CLLocationCoordinate2D,
        to target: CLLocationCoordinate2D
    ) -> Double {
        let φ1 = origin.latitude * .pi / 180
        let φ2 = target.latitude * .pi / 180
        let Δλ = (target.longitude - origin.longitude) * .pi / 180
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Absolute angular separation between two bearings, 0...180.
    static func separation(_ a: Double, _ b: Double) -> Double {
        abs((((a - b + 180).truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360) - 180)
    }

    /// Signed turn from `a` to `b` taking the short way round, -180...180.
    ///
    /// A needle that swings 288° the long way to travel 72° looks broken, so the
    /// compass tracks an unwrapped angle built out of these deltas.
    static func shortestDelta(from a: Double, to b: Double) -> Double {
        let raw = (b - a).truncatingRemainder(dividingBy: 360)
        if raw > 180 { return raw - 360 }
        if raw < -180 { return raw + 360 }
        return raw
    }
}
