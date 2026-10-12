import Foundation
import Observation

/// What `GET /v1/conditions` says about the city: the weather and, when the
/// server has them switched on, SMAT's works notices.
///
/// Context only. None of it is about the water in a fountain, and it carries no
/// field that could be read as a water state; the app words it as "possibly
/// affected" and always with its source and the time it was fetched.
struct Conditions: Codable, Equatable, Sendable {
    var weather: Weather?
    var notices: Notices

    /// Older than this and the weather is not shown: the number would be a guess.
    static let weatherFreshness: TimeInterval = 3 * 3600
    /// The server itself reports "no data" after six hours; so does the app, so a
    /// copy kept on disk by a phone that has been offline for a day says nothing.
    static let noticeFreshness: TimeInterval = 6 * 3600
    /// From this apparent temperature on, the day is called hot.
    static let hotApparentTemperature = 30.0

    struct Weather: Codable, Equatable, Sendable {
        var temperatureC: Double
        var apparentTemperatureC: Double
        var relativeHumidityPercent: Double?
        var apparentTemperatureMaxTodayC: Double?
        /// When Open-Meteo says the reading was taken.
        var observedAt: Date
        /// When our server fetched it.
        var fetchedAt: Date
    }

    struct Notices: Codable, Equatable, Sendable {
        var enabled: Bool
        var fetchedAt: Date?
        var items: [Notice]

        static let off = Notices(enabled: false, fetchedAt: nil, items: [])

        private enum CodingKeys: String, CodingKey { case enabled, fetchedAt, items }

        init(enabled: Bool, fetchedAt: Date?, items: [Notice]) {
            self.enabled = enabled
            self.fetchedAt = fetchedAt
            self.items = items
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = (try? container.decode(Bool.self, forKey: .enabled)) ?? false
            fetchedAt = (try? container.decodeIfPresent(Date.self, forKey: .fetchedAt)) ?? nil
            let lossy = (try? container.decodeIfPresent([Lossy<Notice>].self, forKey: .items)) ?? nil
            items = (lossy ?? []).compactMap(\.value)
        }
    }

    /// One works order, matched to fountains by street name only.
    struct Notice: Codable, Equatable, Sendable, Identifiable {
        var id: String
        /// `waterWorks` or `fountainWorks`; both are worded the same.
        var kind: String
        /// SMAT's address string, as published.
        var street: String
        var fountainIDs: [String]
        /// `YYYY-MM-DD`, a calendar date in Europe/Rome.
        var startedOn: String
        var plannedEnd: String?
        var source: String
        var fetchedAt: Date
    }

    // MARK: What may be shown

    /// The weather, unless it is too old to say anything about now.
    func visibleWeather(now: Date = .now) -> Weather? {
        guard let weather, now.timeIntervalSince(weather.observedAt) <= Self.weatherFreshness else { return nil }
        return weather
    }

    /// The works notices that mention this fountain, only while the feature is on
    /// and the data recent. No data is not "no works": it shows nothing at all.
    func notices(for fountainID: String, now: Date = .now) -> [Notice] {
        guard notices.enabled, let fetched = notices.fetchedAt,
              now.timeIntervalSince(fetched) <= Self.noticeFreshness
        else { return [] }
        return notices.items
            .filter { $0.fountainIDs.contains(fountainID) }
            .sorted { ($0.startedOn, $0.id) > ($1.startedOn, $1.id) }
    }

    /// Whether the day deserves "leve água": the apparent temperature now, or the
    /// day's highest, reaches 30.
    func isHot(_ weather: Weather) -> Bool {
        max(weather.apparentTemperatureC, weather.apparentTemperatureMaxTodayC ?? -.infinity)
            >= Self.hotApparentTemperature
    }

    // MARK: Decoding

    private enum CodingKeys: String, CodingKey { case weather, notices }

    init(weather: Weather?, notices: Notices) {
        self.weather = weather
        self.notices = notices
    }

    /// Forgiving on purpose: a weather block this app cannot read costs the
    /// weather, not the notices, and a notice it cannot read costs that notice.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weather = (try? container.decodeIfPresent(Weather.self, forKey: .weather)) ?? nil
        notices = (try? container.decodeIfPresent(Notices.self, forKey: .notices)) ?? .off
    }
}

/// An element that decodes or is nothing, so one bad record does not take the
/// rest of its list with it.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

// MARK: - Loading

/// Fetches the conditions, keeps the last good copy on disk, and refreshes it
/// every 15 minutes while the app is in front.
///
/// Silent by design: when the server cannot be reached the old copy stays, its
/// own timestamps decide whether it may still be shown, and nothing is announced.
@MainActor
@Observable
final class ConditionsStore {
    /// Open-Meteo's own rule: no more often than every 15 minutes.
    static let refreshInterval: Duration = .seconds(15 * 60)
    /// Coming back to the app does not ask again within this time.
    static let minimumSpacing: TimeInterval = 60

    private(set) var conditions: Conditions?
    /// Moves on every attempt, so views that hide stale data look again.
    private(set) var lastAttempt: Date?

    @ObservationIgnored private let client: APIClient?
    @ObservationIgnored private let cacheURL: URL?
    @ObservationIgnored private let clock: @Sendable () -> Date

    init(client: APIClient?, cacheURL: URL? = nil, clock: @escaping @Sendable () -> Date = { .now }) {
        self.client = client
        self.cacheURL = cacheURL
        self.clock = clock
        conditions = cacheURL.flatMap(Self.load)
    }

    /// The real thing, pointed at the same server as the community. A Debug build
    /// with no `-toret-api` has none, and shows no conditions.
    static func standard(arguments: [String] = ProcessInfo.processInfo.arguments) -> ConditionsStore {
        guard let baseURL = APIConfiguration.resolvedBaseURL(arguments: arguments) else {
            return ConditionsStore(client: nil)
        }
        return ConditionsStore(
            client: APIClient(baseURL: baseURL),
            cacheURL: FilePersistence.defaultURL("conditions-cache.json")
        )
    }

    // MARK: Reading

    /// The weather, or nil when there is none or it is too old.
    func weather(now: Date? = nil) -> Conditions.Weather? {
        conditions?.visibleWeather(now: now ?? clock())
    }

    var isHot: Bool {
        guard let weather = weather(), let conditions else { return false }
        return conditions.isHot(weather)
    }

    func notices(for fountainID: String, now: Date? = nil) -> [Conditions.Notice] {
        conditions?.notices(for: fountainID, now: now ?? clock()) ?? []
    }

    // MARK: Refreshing

    /// Asks the server once. A failure of any kind keeps what there was.
    func refresh(force: Bool = false) async {
        guard let client else { return }
        let now = clock()
        if !force, let lastAttempt, now.timeIntervalSince(lastAttempt) < Self.minimumSpacing { return }
        lastAttempt = now
        guard let response = try? await client.send("GET", "/v1/conditions"), response.status == 200,
              let fresh = try? FilePersistence.decoder.decode(Conditions.self, from: response.data)
        else { return }
        conditions = fresh
        if let cacheURL { Self.store(fresh, at: cacheURL) }
    }

    /// Refreshes now and then every 15 minutes, until the task is cancelled. Run
    /// it from a `.task` that follows the scene phase, so it only ticks while the
    /// app is in front.
    func run() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }

    // MARK: Disk

    private static func load(_ url: URL) -> Conditions? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? FilePersistence.decoder.decode(Conditions.self, from: data)
    }

    private static func store(_ conditions: Conditions, at url: URL) {
        guard let data = try? FilePersistence.encoder.encode(conditions) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
