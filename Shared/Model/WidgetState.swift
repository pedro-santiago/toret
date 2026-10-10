import Foundation

/// The cycle button's memory, in the shared container.
///
/// Kept in the container (rather than in the widget's own defaults) so that a
/// build without the app group — a Personal Team install — degrades to "each
/// process remembers its own", and the widget, which is the only reader, still
/// works.
enum CycleStore {
    static let key = "toret.widget.cycle"

    static func load(from defaults: UserDefaults = Store.defaults) -> CycleState {
        guard let stored = defaults.dictionary(forKey: key),
              let index = stored["index"] as? Int,
              let stamp = stored["date"] as? TimeInterval
        else { return .initial }
        return CycleState(index: index, date: Date(timeIntervalSince1970: stamp))
    }

    @discardableResult
    static func advance(
        count: Int, defaults: UserDefaults = Store.defaults, now: Date = .now
    ) -> CycleState {
        let next = load(from: defaults).advanced(count: count, now: now)
        defaults.set(
            ["index": next.index, "date": next.date.timeIntervalSince1970], forKey: key
        )
        return next
    }
}

/// How long a widget's reading is good for.
enum RefreshPolicy {
    /// Between timeline reloads. The app's own fixes reload it sooner; this is
    /// the floor, and the system treats it as a hint, not a promise.
    static func interval(for provenance: FixProvenance) -> TimeInterval {
        switch provenance {
        case .live: 10 * 60
        case .approximate: 15 * 60
        // Waiting for the first fix is the one case worth looking at again soon.
        case .centre(denied: false): 20 * 60
        // Nothing changes until the user changes a setting or flies home.
        case .centre(denied: true), .outsideTurin: 60 * 60
        }
    }
}

extension Fountain {
    /// A widget has no focus ring, so VoiceOver gets the whole sentence at once.
    var widgetSpoken: String {
        let minutes = walkingMinutes
        let walk = String(localized: "\(minutes) minutos a pé")
        let sentence = String(
            localized: "\(place), \(DistanceFormat.spoken(distance)) para \(Bearing.spokenCardinal(bearing)), \(walk)"
        )
        return state == .unknown ? sentence : sentence + ", " + state.label.lowercased()
    }
}
