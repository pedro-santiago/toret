import CoreGraphics
import Foundation

// One illustration per fountain, composed and never stored.
//
// Seven hundred and twenty-three fountains do not need seven hundred and
// twenty-three pictures. They need a handful of printed plates, a few backdrops
// and a deterministic way to lay them out, so that the same fountain always gets the
// same print and the one next door gets a different one. This file is the
// deterministic part: a pure value computed from three facts about a fountain,
// its OpenStreetMap node id, its kind and its neighbourhood.
//
// The honesty rule: water state is NOT an input. A plate shows the fountain as an
// object. It never draws a stream, a puddle, a crack or anything else that would
// tell the reader what the water is doing; that is the job of `StateMark` and the
// community report, and a pretty picture must never contradict them.

/// A small, stable hash stream. Swift's own `Hasher` is seeded per launch, so a
/// fountain would get a different picture every time the app opened.
struct PlateRandom: Sendable {
    private var state: UInt64

    /// FNV-1a over the UTF-8 of `text`.
    init(_ text: String) {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        state = hash
    }

    /// SplitMix64.
    mutating func next() -> UInt64 {
        state = state &+ 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }

    /// A value in `0 ..< 1`.
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    mutating func value(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }

    mutating func bool() -> Bool { next() & 1 == 1 }
}

/// What stands behind the fountain.
enum PlateBackdrop: Hashable, Sendable {
    /// A building or a range from the app's skyline kit.
    case landmark(TurinLandmark)
    /// The poster's chequered diamond, grown to fill the plate.
    case checker
    /// Three tall vertical bands, a flat geometric motif with no place in it.
    case bands

    /// Every backdrop a plate can have, for tests and contact sheets.
    static let all: [PlateBackdrop] =
        [.landmark(.mole), .landmark(.duomo), .landmark(.superga), .landmark(.granMadre),
         .landmark(.palazzoMadama), .landmark(.portaPalatina), .landmark(.portaNuova),
         .landmark(.sanCarlo), .landmark(.cappuccini), .landmark(.bridge),
         .landmark(.arcades), .landmark(.alps), .checker, .bands]
}

/// Which inks the plate is printed in: the big field, the sun, the dot, the ground.
enum PlatePairing: Int, CaseIterable, Hashable, Sendable {
    case daylight, gold, river, ochre, brick
}

/// Everything needed to draw one fountain's plate, in fractions of its frame.
struct FountainPlateSpec: Hashable, Sendable {
    // The subject: one of the printed plates of this kind of fountain.
    var kind: FountainKind
    var variant: Int
    var mirrored: Bool

    // The scene.
    var backdrop: PlateBackdrop
    var pairing: PlatePairing
    /// Horizontal position of the backdrop, 0 left to 1 right.
    var backdropX: Double
    /// 0.8 to 1: how much of the available height the backdrop takes.
    var backdropScale: Double
    /// Where the subject stands, 0.5 centred.
    var subjectX: Double

    // The sun and the red dot, as fractions of the plate.
    var sunX: Double
    var sunY: Double
    /// Radius as a fraction of the plate's height.
    var sunRadius: Double
    var dotX: Double
    var dotY: Double
    var dotRadius: Double

    /// Thin bands on the ground. Decoration, the same for every fountain whatever
    /// the water is doing.
    var stripes: Int

    /// How many printed plates exist for each kind. These are the image sets
    /// `plate-<kind>-a`, `-b`, and so on in the asset catalogue.
    static let variantCounts: [FountainKind: Int] = [.toret: 4, .fountain: 3, .bubbler: 3, .refill: 3]

    static func assetName(kind: FountainKind, variant: Int) -> String {
        "plate-\(kind.rawValue)-\(Character(UnicodeScalar(UInt8(97 + variant))))"
    }

    var assetName: String { Self.assetName(kind: kind, variant: variant) }

    /// The neighbourhoods and what stands behind them. Keyed by the name
    /// OpenStreetMap and the catalogue use, not the localised one.
    static let backdrops: [String: PlateBackdrop] = [
        "Centro": .landmark(.duomo), "Crocetta": .landmark(.portaNuova),
        "San Salvario": .landmark(.sanCarlo), "Borgo Po": .landmark(.granMadre),
        "Madonna del Pilone": .landmark(.superga), "Borgo San Pietro": .landmark(.cappuccini),
        "Vanchiglia": .landmark(.mole), "Vanchiglietta": .landmark(.bridge),
        "Aurora": .landmark(.portaPalatina), "Barriera di Milano": .checker,
        "Regio Parco": .landmark(.bridge), "Borgo Vittoria": .landmark(.alps),
        "Madonna di Campagna": .landmark(.alps), "Lucento": .bands,
        "Vallette": .landmark(.superga), "Parella": .landmark(.alps),
        "Pozzo Strada": .landmark(.arcades), "Cit Turin": .landmark(.palazzoMadama),
        "Santa Rita": .checker, "Mirafiori Nord": .bands, "Mirafiori Sud": .landmark(.arcades),
        "Lingotto": .landmark(.portaNuova), "Nizza Millefonti": .landmark(.bridge),
        "Borgo San Paolo": .landmark(.arcades), "Cenisia": .landmark(.portaPalatina),
        "Campidoglio": .landmark(.palazzoMadama), "Filadelfia": .checker,
        "San Donato": .landmark(.mole), "Barriera di Lanzo": .landmark(.alps),
        "Rebaudengo": .bands, "Barca": .landmark(.bridge), "Falchera": .landmark(.alps),
        "Borgata Paradiso": .landmark(.superga), "Villaretto": .landmark(.alps),
        "Sant'Anna": .landmark(.cappuccini),
    ]

    /// Backdrops for a fountain whose neighbourhood is unknown: nothing in the city,
    /// only the geometry.
    private static let placeless: [PlateBackdrop] = [.checker, .bands, .landmark(.arcades)]

    /// Neighbourhoods in a fixed order, so a zone always lands on the same pairing.
    private static let zoneOrder = backdrops.keys.sorted()

    init(id: String, kind: FountainKind, zone: String?) {
        var rng = PlateRandom(id)

        self.kind = kind
        let count = Self.variantCounts[kind] ?? 1
        variant = rng.int(in: 0 ... count - 1)
        mirrored = rng.bool()

        if let zone, let known = Self.backdrops[zone] {
            backdrop = known
        } else {
            backdrop = Self.placeless[rng.int(in: 0 ... Self.placeless.count - 1)]
        }

        // The zone picks a pair of pairings and the fountain picks one of them, so
        // neighbours share a family of inks but not always the same print.
        let zoneIndex = zone.flatMap { Self.zoneOrder.firstIndex(of: $0) } ?? Int(rng.next() % 7)
        let cases = PlatePairing.allCases
        let picked = cases[(zoneIndex * 2 + (rng.bool() ? 1 : 0)) % cases.count]
        // A brick-red post must not stand against a brick-red sun or sky.
        pairing = kind == .refill && [.gold, .ochre, .brick].contains(picked)
            ? (picked == .gold ? .daylight : .river) : picked

        subjectX = rng.value(in: 0.44 ... 0.56)
        // The backdrop leans to whichever side the subject is not on, but never to the
        // edge: a landmark cut in half is a landmark nobody recognises.
        backdropX = subjectX < 0.5 ? rng.value(in: 0.58 ... 0.76) : rng.value(in: 0.24 ... 0.42)
        backdropScale = rng.value(in: 0.82 ... 1.0)

        sunRadius = rng.value(in: 0.17 ... 0.30)
        sunX = rng.value(in: 0.2 ... 0.8)
        sunY = rng.value(in: 0.2 ... 0.42)
        dotRadius = rng.value(in: 0.028 ... 0.05)
        // The dot goes to the corner the sun is not in.
        dotX = sunX < 0.5 ? rng.value(in: 0.78 ... 0.92) : rng.value(in: 0.08 ... 0.22)
        dotY = rng.value(in: 0.1 ... 0.3)

        stripes = rng.int(in: 2 ... 4)
    }
}
