import Foundation

/// A quick property of the experience, picked from a short fixed list.
///
/// Fixed rather than free text so a rating is comparable across fountains and
/// readable in any language.
enum ReportTag: String, Codable, Sendable, CaseIterable, Identifiable {
    case cold, clean, strongFlow, easyToReach, shade, dirty, hardToFind

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cold: String(localized: "Água gelada")
        case .clean: String(localized: "Limpa")
        case .strongFlow: String(localized: "Bom fluxo")
        case .easyToReach: String(localized: "Fácil de alcançar")
        case .shade: String(localized: "À sombra")
        case .dirty: String(localized: "Suja")
        case .hardToFind: String(localized: "Difícil de achar")
        }
    }

    var isPositive: Bool { self != .dirty && self != .hardToFind }
}

/// One person's word about one fountain: what the water was doing, how they rate
/// it, and, optionally, a line of their own.
///
/// This is the unit of the community feed. It carries no name, no account and no
/// position — only which fountain, when, and the author's anonymous handle.
struct Report: Identifiable, Codable, Hashable, Sendable {
    /// Longest note accepted, in characters.
    static let maximumNoteLength = 140

    let id: String
    let fountainID: String
    let state: WaterState
    /// 1...5, or nil when the person only reported the water.
    let rating: Int?
    let tags: [ReportTag]
    let note: String
    let date: Date
    /// Anonymous and stable per device or iCloud account: "Visitante 4F2A".
    let author: String
    /// True for reports this device wrote.
    var isMine: Bool

    init(
        id: String = UUID().uuidString,
        fountainID: String,
        state: WaterState,
        rating: Int? = nil,
        tags: [ReportTag] = [],
        note: String = "",
        date: Date = .now,
        author: String,
        isMine: Bool = true
    ) {
        self.id = id
        self.fountainID = fountainID
        self.state = state
        self.rating = rating.map { min(5, max(1, $0)) }
        self.tags = tags
        self.note = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumNoteLength))
        self.date = date
        self.author = author
        self.isMine = isMine
    }
}

/// What a fountain's reports add up to — the only community data a pin, a widget
/// or a notification needs.
struct CommunitySummary: Hashable, Sendable {
    /// What the freshest report said, or `.unknown` once it has gone stale.
    var state: WaterState
    /// When that freshest report was made.
    var latestDate: Date?
    /// Mean rating, 1...5.
    var average: Double?
    var ratingCount: Int
    var reportCount: Int

    static let empty = CommunitySummary(
        state: .unknown, latestDate: nil, average: nil, ratingCount: 0, reportCount: 0
    )

    /// How long a report about the water is believed.
    ///
    /// A fountain that was dry yesterday morning may be running now, and one that
    /// was running last week says nothing about today. A day and a half covers
    /// "somebody passed it this morning" without turning into a rumour.
    static let freshness: TimeInterval = 36 * 3600

    /// Folds a fountain's reports into one summary. The newest report about the
    /// water decides the state; every rating counts towards the average.
    static func summarising(_ reports: [Report], now: Date = .now) -> CommunitySummary {
        guard !reports.isEmpty else { return .empty }
        // A rating with no word about the water says nothing about the water, so
        // it must not be what resets "running" to "unknown".
        let newest = reports.filter { $0.state != .unknown }.max { $0.date < $1.date }
            ?? reports.max { $0.date < $1.date }
        let fresh = newest.flatMap { now.timeIntervalSince($0.date) <= freshness ? $0 : nil }
        let ratings = reports.compactMap(\.rating)
        return CommunitySummary(
            state: fresh?.state ?? .unknown,
            latestDate: newest?.date,
            average: ratings.isEmpty ? nil : Double(ratings.reduce(0, +)) / Double(ratings.count),
            ratingCount: ratings.count,
            reportCount: reports.count
        )
    }
}

extension CommunitySummary {
    /// Where the figure above it comes from, in a plain sentence: "Relato há 2 h",
    /// "Último relato há 3 dias", "Sem relatos". Sentence case: callers that set it
    /// in capitals do that themselves.
    ///
    /// A state without a provenance is a rumour, so the pin never says more than
    /// this line can back up.
    var provenance: String {
        guard let latestDate else { return String(localized: "Sem relatos") }
        let ago = Formatting.relative(latestDate)
        return state == .unknown
            ? String(localized: "Último relato \(ago)")
            : String(localized: "Relato \(ago)")
    }

    /// "4,6", or nothing when nobody has rated it.
    var ratingValue: String? {
        guard let average, ratingCount > 0 else { return nil }
        return Formatting.rating(average)
    }

    /// "1 avaliação" / "12 avaliações": the plural is the catalog's, so Italian and
    /// English get their own rules.
    static func ratingCountLabel(_ count: Int) -> String {
        String(localized: "\(count) avaliações")
    }

    /// "4,6 · 12 avaliações", or nothing when nobody has rated it.
    var ratingLine: String? {
        guard let ratingValue else { return nil }
        return "\(ratingValue) · \(Self.ratingCountLabel(ratingCount))"
    }
}
