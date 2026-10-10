import Foundation

extension FixProvenance {
    /// One short line for the tiles with no room for ``note``: why there is no
    /// distance from *you* on the widget.
    var shortNote: String? {
        switch self {
        case .live, .approximate:
            nil
        case .centre(denied: true):
            String(localized: "Localização desligada")
        case .centre(denied: false):
            String(localized: "Abra o Toret para medir")
        case let .outsideTurin(kilometres):
            String(localized: "Você está a \(kilometres) km")
        }
    }
}

extension WidgetReading {
    /// Whether the figures on the widget are measured from the user.
    ///
    /// When they are not — no permission, no fix yet, a fix far from Turin — the
    /// bearing is meaningless too: an arrow from Piazza San Carlo points at
    /// nothing the reader can see. Those widgets lead with the *name* and say
    /// plainly where the number is measured from.
    var isPersonal: Bool { provenance.isMeasuringFromUser }

    /// What VoiceOver reads for one fountain on this widget.
    func spoken(_ fountain: Fountain) -> String {
        guard isPersonal else {
            let from = String(localized: "\(DistanceFormat.spoken(fountain.distance)) do centro de Turim")
            return "\(fountain.place), \(fountain.zone), \(from)"
        }
        return fountain.widgetSpoken
    }
}

extension Fountain {
    /// The line under a fountain's name where a widget has room for one, when the
    /// distance is *not* the reader's own: the figure, labelled as the old town's.
    var distanceFromCentre: String {
        String(localized: "\(DistanceFormat.short(distance)) do centro")
    }
}
