import Foundation

// The compass ring already knows seven landmarks by key. This is the bridge from
// those keys to the drawings, so the ring and the map can show the real building
// instead of a generic dome or square.

extension TurinLandmark {
    /// The drawing for a ring landmark.
    init(_ key: Landmark.Key) {
        switch key {
        case .duomo: self = .duomo
        case .mole: self = .mole
        case .superga: self = .superga
        case .cappuccini: self = .cappuccini
        case .portaNuova: self = .portaNuova
        case .alps: self = .alps
        case .portePalatine: self = .portaPalatina
        }
    }

    /// The drawing for a landmark known only by its ring label ("MOLE", "ALPI"),
    /// in whatever language the label is in.
    static func forRingName(_ name: String) -> TurinLandmark? {
        Landmark.all(from: Catalogue.anchor).first { $0.name == name }.map { TurinLandmark($0.key) }
    }
}

extension Landmark {
    /// The drawing that stands for this landmark.
    var drawn: TurinLandmark { TurinLandmark(key) }
}
