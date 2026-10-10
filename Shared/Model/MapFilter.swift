/// The chips above the map.
///
/// These narrow *emphasis* rather than membership: a fountain that does not match
/// stays on the map, just recessed. Hiding one would be the one thing worse than
/// walking to it — you would walk to it twice.
///
/// Every chip is backed by something the data actually knows. A chip that matched
/// everything, or that claimed "24 h" without a source, would be a promise the
/// catalogue cannot keep.
enum MapFilter: String, CaseIterable, Identifiable {
    /// Hides the ones the community has reported dry.
    case notDry = "Sem relato de seca"
    case accessible = "Acessível"
    case bottle = "Para garrafa"
    case dogs = "Para cães"

    var id: String { rawValue }

    func matches(_ fountain: Fountain) -> Bool {
        switch self {
        case .notDry: fountain.state != .dry
        case .accessible: fountain.wheelchair == .yes
        case .bottle: fountain.hasBottleFiller
        case .dogs: fountain.allowsDogs
        }
    }
}
