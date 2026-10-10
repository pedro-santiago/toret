import Foundation

extension Bearing {
    /// The wind spelled out for a voice: "noroeste".
    static func spokenCardinal(_ degrees: Double) -> String {
        let names = [
            "norte", "nordeste", "leste", "sudeste", "sul", "sudoeste", "oeste", "noroeste",
        ]
        let normalised = (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        return names[Int((normalised + 22.5) / 45) % 8]
    }
}

/// What Siri and Shortcuts say.
///
/// A spoken answer is read once, by someone walking, and cannot be re-read. So it
/// leads with the thing they asked for, says where the figure was measured from
/// whenever that is not their own position, and mentions the water only when a
/// person has actually reported on it.
enum SpokenAnswer {
    static func nearest(_ reading: WidgetReading) -> String {
        if reading.savedIsEmpty {
            return String(localized: "Você ainda não salvou nenhuma fonte.")
        }
        guard let fountain = reading.featured else {
            return String(localized: "Não encontrei nenhuma fonte para medir.")
        }

        var sentences: [String] = []
        switch reading.provenance {
        case .live:
            break
        case .approximate:
            sentences.append(String(localized: "Com a sua localização aproximada."))
        case .centre:
            sentences.append(String(localized: "Sem a sua localização, medindo a partir do centro de Turim."))
        case let .outsideTurin(kilometres):
            sentences.append(String(localized: "Você está a \(kilometres) quilômetros de Turim, então estou medindo a partir do centro."))
        }

        let distance = DistanceFormat.spoken(fountain.distance)
        let direction = Bearing.spokenCardinal(fountain.bearing)
        let minutes = fountain.walkingMinutes
        let walk = minutes == 1
            ? String(localized: "cerca de 1 minuto a pé")
            : String(localized: "cerca de \(minutes) minutos a pé")
        let lead = reading.source == .saved
            ? String(localized: "Sua fonte salva mais próxima é")
            : String(localized: "A fonte mais próxima é")
        sentences.append(String(localized: "\(lead) \(fountain.place), a \(distance) para \(direction), \(walk)."))

        if fountain.state != .unknown {
            sentences.append(String(localized: "Relato recente da comunidade: \(fountain.state.label.lowercased())."))
        }
        if let hint = reading.lookHint {
            sentences.append(hint + ".")
        }
        return sentences.joined(separator: " ")
    }
}
