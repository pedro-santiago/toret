/// The chips above the map.
///
/// These narrow *emphasis* rather than membership: a fountain that does not match
/// stays on the map, just recessed. Hiding one would be the one thing worse than
/// walking to it — you would walk to it twice.
///
/// Every chip is backed by something the data actually knows. A chip that matched
/// everything, or that claimed "24 h" without a source, would be a promise the
/// catalogue cannot keep.
///
/// The raw value is the key the choice is *stored* under (`Preferences.filters`)
/// and never changes; what the chip says is ``title``, which follows the language.
/// Builds before the app was translated stored the Portuguese title instead, so
/// ``init(stored:)`` reads those too.
enum MapFilter: String, CaseIterable, Identifiable {
    /// Hides the ones the community has reported dry.
    case notDry
    case accessible
    case bottle
    case dogs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notDry: String(localized: "Sem relato de seca")
        case .accessible: String(localized: "Acessível")
        case .bottle: String(localized: "Para garrafa")
        case .dogs: String(localized: "Para cães")
        }
    }

    /// Reads a stored choice: the stable key, or the Portuguese title that the
    /// first versions stored. Anything else — the chips that no longer exist —
    /// is dropped.
    init?(stored: String) {
        if let current = MapFilter(rawValue: stored) {
            self = current
            return
        }
        switch stored {
        case "Sem relato de seca": self = .notDry
        case "Acessível": self = .accessible
        case "Para garrafa": self = .bottle
        case "Para cães": self = .dogs
        default: return nil
        }
    }

    func matches(_ fountain: Fountain) -> Bool {
        switch self {
        case .notDry: fountain.state != .dry
        case .accessible: fountain.wheelchair == .yes
        case .bottle: fountain.hasBottleFiller
        case .dogs: fountain.allowsDogs
        }
    }
}
