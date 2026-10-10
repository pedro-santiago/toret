import Foundation

extension CommunitySummary {
    /// What the community has said about the water, as one plain sentence.
    ///
    /// "Água corrente, relato há 2 h". "Sem relato recente. Último relato há 3 dias".
    /// The state never appears without the age of the word behind it, because a
    /// state with no provenance is a rumour.
    func sentence(now: Date = .now, locale: Locale = Locale(identifier: "pt_BR")) -> String {
        guard let latestDate else { return state.label }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .abbreviated
        let ago = formatter.localizedString(for: latestDate, relativeTo: now)
        if state == .unknown {
            return String(localized: "\(state.label). Último relato \(ago)")
        }
        return String(localized: "\(state.label), relato \(ago)")
    }
}
