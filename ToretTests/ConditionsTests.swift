import Foundation
import Testing

@testable import Toret

/// The example from docs/backend/api.md, section 6.7.
private let apiExample = """
{
  "weather": {
    "temperatureC": 24.1, "apparentTemperatureC": 26.3, "relativeHumidityPercent": 48,
    "apparentTemperatureMaxTodayC": 29.5,
    "observedAt": "2026-10-12T13:30:00Z", "fetchedAt": "2026-10-12T13:41:12Z",
    "attribution": "Weather data by Open-Meteo.com", "licence": "CC BY 4.0",
    "licenceURL": "https://creativecommons.org/licenses/by/4.0/", "sourceURL": "https://open-meteo.com/"
  },
  "notices": {
    "enabled": true, "fetchedAt": "2026-10-12T13:05:00Z",
    "items": [{
      "id": "a1b2c3d4e5f6", "kind": "waterWorks", "street": "Corso Vittorio Emanuele II",
      "fountainIDs": ["421310659"], "match": "street", "startedOn": "2026-10-05",
      "plannedEnd": "2026-10-23", "source": "SMAT S.p.A., Mappa Cantieri", "fetchedAt": "2026-10-12T13:05:00Z"
    }]
  }
}
"""

private let observed = Date(timeIntervalSince1970: 1_791_811_800)  // 2026-10-12T13:30:00Z
private let pt = Locale(identifier: "pt_BR")

private func decode(_ text: String) throws -> Conditions {
    try FilePersistence.decoder.decode(Conditions.self, from: Data(text.utf8))
}

private func weather(
    _ temperature: Double = 21, apparent: Double = 20, max: Double? = nil, observedAt: Date = observed
) -> Conditions.Weather {
    Conditions.Weather(
        temperatureC: temperature, apparentTemperatureC: apparent, relativeHumidityPercent: 50,
        apparentTemperatureMaxTodayC: max, observedAt: observedAt, fetchedAt: observedAt.addingTimeInterval(700)
    )
}

private func notice(_ id: String = "n1", fountains: [String] = ["421310659"], started: String = "2026-10-05") -> Conditions.Notice {
    Conditions.Notice(
        id: id, kind: "waterWorks", street: "Corso Vittorio Emanuele II", fountainIDs: fountains,
        startedOn: started, plannedEnd: nil, source: "SMAT S.p.A., Mappa Cantieri", fetchedAt: observed
    )
}

@Suite("Conditions model")
struct ConditionsModelTests {
    @Test("The documented response decodes")
    func example() throws {
        let conditions = try decode(apiExample)
        let weather = try #require(conditions.weather)
        #expect(weather.temperatureC == 24.1)
        #expect(weather.apparentTemperatureC == 26.3)
        #expect(weather.relativeHumidityPercent == 48)
        #expect(weather.apparentTemperatureMaxTodayC == 29.5)
        #expect(weather.observedAt == observed)
        #expect(conditions.notices.enabled)
        #expect(conditions.notices.items.map(\.id) == ["a1b2c3d4e5f6"])
        #expect(conditions.notices.items.first?.fountainIDs == ["421310659"])
        #expect(conditions.notices.items.first?.plannedEnd == "2026-10-23")
    }

    @Test("Unknown fields and kinds are ignored; a bad record costs only itself")
    func forgiving() throws {
        let conditions = try decode("""
        {"future":true,
         "weather":{"temperatureC":"warm"},
         "notices":{"enabled":true,"fetchedAt":"2026-10-12T13:05:00Z","extra":1,"items":[
           {"id":"a","kind":"somethingNew","street":"Via Roma","fountainIDs":[],"startedOn":"2026-10-05","source":"S","fetchedAt":"2026-10-12T13:05:00Z","more":1},
           {"id":"b","street":"missing the other fields"}
         ]}}
        """)
        #expect(conditions.weather == nil)
        #expect(conditions.notices.items.map(\.id) == ["a"])
    }

    @Test("A response with no weather or the features off decodes to nothing to show")
    func empty() throws {
        let off = try decode(#"{"weather":null,"notices":{"enabled":false,"items":[]}}"#)
        #expect(off.weather == nil)
        #expect(!off.notices.enabled)
        #expect(off.notices(for: "421310659", now: observed).isEmpty)
        #expect(try decode("{}").notices == .off)
    }

    @Test("It round-trips through the disk cache")
    func roundTrip() throws {
        let conditions = try decode(apiExample)
        let data = try FilePersistence.encoder.encode(conditions)
        #expect(try FilePersistence.decoder.decode(Conditions.self, from: data) == conditions)
    }

    // MARK: Staleness

    @Test("Weather is shown for three hours and not a minute longer")
    func weatherStaleness() {
        let conditions = Conditions(weather: weather(), notices: .off)
        #expect(conditions.visibleWeather(now: observed) != nil)
        #expect(conditions.visibleWeather(now: observed.addingTimeInterval(3 * 3600)) != nil)
        #expect(conditions.visibleWeather(now: observed.addingTimeInterval(3 * 3600 + 1)) == nil)
        #expect(conditions.visibleWeather(now: observed.addingTimeInterval(-300)) != nil, "a clock a little behind is not stale")
    }

    @Test("Notices need the feature on, a fetch time, and fresh data")
    func noticeRules() {
        let items = [notice()]
        let fetched = observed
        func conditions(enabled: Bool = true, fetchedAt: Date? = fetched) -> Conditions {
            Conditions(weather: nil, notices: .init(enabled: enabled, fetchedAt: fetchedAt, items: items))
        }
        #expect(conditions().notices(for: "421310659", now: fetched).count == 1)
        #expect(conditions(enabled: false).notices(for: "421310659", now: fetched).isEmpty)
        #expect(conditions(fetchedAt: nil).notices(for: "421310659", now: fetched).isEmpty)
        #expect(conditions().notices(for: "421310659", now: fetched.addingTimeInterval(6 * 3600)).count == 1)
        #expect(conditions().notices(for: "421310659", now: fetched.addingTimeInterval(6 * 3600 + 1)).isEmpty)
    }

    @Test("A notice shows only on a fountain it matched, newest start first")
    func matching() {
        let conditions = Conditions(weather: nil, notices: .init(enabled: true, fetchedAt: observed, items: [
            notice("old", fountains: ["1", "2"], started: "2026-09-01"),
            notice("new", fountains: ["1"], started: "2026-10-05"),
            notice("elsewhere", fountains: ["3"]),
            notice("nothing", fountains: []),
        ]))
        #expect(conditions.notices(for: "1", now: observed).map(\.id) == ["new", "old"])
        #expect(conditions.notices(for: "2", now: observed).map(\.id) == ["old"])
        #expect(conditions.notices(for: "9", now: observed).isEmpty)
    }

    @Test("A hot day is an apparent temperature of 30 or more, now or at the day's highest")
    func hot() {
        let conditions = Conditions(weather: nil, notices: .off)
        #expect(!conditions.isHot(weather(28, apparent: 29.9)))
        #expect(conditions.isHot(weather(28, apparent: 30)))
        #expect(conditions.isHot(weather(22, apparent: 24, max: 31.5)))
        #expect(!conditions.isHot(weather(22, apparent: 24, max: 29.9)))
        // The air temperature alone is not what the rule reads.
        #expect(!conditions.isHot(weather(35, apparent: 29)))
    }
}

@Suite("Conditions wording")
struct ConditionsCopyTests {
    @Test("The weather line says where, how warm, the source and the time")
    func line() {
        let text = ConditionsCopy.weatherLine(weather(21.4, apparent: 19.6), hot: false, locale: pt)
        #expect(text.hasPrefix("Turim agora: 21 °C, sensação 20 °C · Open-Meteo, "))
        #expect(text.hasSuffix(Formatting.clock(observed, locale: pt)))
        #expect(!text.contains("Dia quente"))
    }

    @Test("The hot-day sentence is added only on a hot day")
    func hotDay() {
        let text = ConditionsCopy.weatherLine(weather(31, apparent: 33), hot: true, locale: pt)
        #expect(text.hasSuffix(". Dia quente: leve água."))
    }

    @Test("Temperatures round to whole degrees and never read -0")
    func rounding() {
        #expect(ConditionsCopy.degrees(-0.4) == 0)
        #expect(ConditionsCopy.degrees(20.5) == 21)
        #expect(ConditionsCopy.degrees(-3.6) == -4)
    }

    @Test("VoiceOver hears the degrees spelled out and the source")
    func spoken() {
        let text = ConditionsCopy.weatherSpoken(weather(21, apparent: 20), hot: false, locale: pt)
        #expect(text.contains("21 graus"))
        #expect(text.contains("Fonte: Open-Meteo"))
    }

    @Test("The works note names the street, the start, the source and the time, and says 'may be affected'")
    func worksNotice() {
        let text = ConditionsCopy.worksNotice(notice(), locale: pt)
        #expect(text.hasPrefix("A SMAT lista uma obra perto de Corso Vittorio Emanuele II, iniciada em "))
        #expect(text.contains("2026"))
        #expect(text.contains("O abastecimento próximo pode ser afetado."))
        #expect(text.hasSuffix("Fonte: SMAT, \(Formatting.clock(observed, locale: pt))"))
    }

    @Test("No wording the conditions use can be read as a water state")
    func honesty() {
        let texts = [
            ConditionsCopy.weatherLine(weather(33, apparent: 35), hot: true, locale: pt),
            ConditionsCopy.weatherSpoken(weather(33, apparent: 35), hot: true, locale: pt),
            ConditionsCopy.worksNotice(notice(), locale: pt),
        ].map { $0.lowercased() }
        for text in texts {
            for word in ["seca", "sem água", "desligad", "corrente", "dry", "off"] {
                #expect(!text.contains(word), "\"\(text)\" contains \(word)")
            }
        }
    }

    @Test("The start date is a Rome calendar date, the same wherever the phone is")
    func dates() {
        #expect(ConditionsCopy.startedOn("2026-10-05", locale: Locale(identifier: "en_US")) == "Oct 5, 2026")
        #expect(ConditionsCopy.startedOn("2026-10-05", locale: Locale(identifier: "it_IT"))?.contains("5") == true)
        #expect(ConditionsCopy.startedOn("not a date") == nil)
    }
}

@Suite("Conditions store")
@MainActor
struct ConditionsStoreTests {
    private func store(
        _ server: StubServer, clock: TestClock, cache: URL? = nil
    ) -> ConditionsStore {
        ConditionsStore(client: server.client(clock: { clock.now }), cacheURL: cache, clock: { clock.now })
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("toret-conditions-\(UUID().uuidString).json")
    }

    @Test("A refresh loads, caches on disk, and a new store starts from the cache")
    func loadAndCache() async throws {
        let clock = TestClock(observed.addingTimeInterval(600))
        let server = StubServer { _ in .json(200, apiExample) }
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let first = store(server, clock: clock, cache: url)
        #expect(first.weather() == nil)
        await first.refresh()
        #expect(first.weather()?.temperatureC == 24.1)
        #expect(first.notices(for: "421310659").count == 1)
        #expect(server.requests.first?.path == "/v1/conditions")

        let second = store(StubServer(), clock: clock, cache: url)
        #expect(second.weather()?.temperatureC == 24.1, "shown before any request has answered")
    }

    @Test("Unreachable, malformed or refused: the old copy stays, silently")
    func failuresKeepWhatThereWas() async {
        let clock = TestClock(observed.addingTimeInterval(600))
        let server = StubServer { _ in .json(200, apiExample) }
        let store = store(server, clock: clock)
        await store.refresh()

        for reply in [StubReply.fail(.notConnectedToInternet), .json(200, "{oops"), .json(500, "{}"), .json(429, "{}"), .json(404, "{}")] {
            server.respond { _ in reply }
            clock.advance(120)
            await store.refresh()
            #expect(store.weather()?.temperatureC == 24.1)
        }
    }

    @Test("The cached copy hides itself as it ages, with no request at all")
    func ageing() async {
        let clock = TestClock(observed.addingTimeInterval(600))
        let server = StubServer { _ in .json(200, apiExample) }
        let store = store(server, clock: clock)
        await store.refresh()
        #expect(store.weather() != nil)
        #expect(store.notices(for: "421310659").count == 1)

        clock.advance(3 * 3600)   // 3 h 10 after the reading
        #expect(store.weather() == nil)
        #expect(store.notices(for: "421310659").count == 1)

        clock.advance(3 * 3600)   // 6 h 10 after the notices were fetched
        #expect(store.notices(for: "421310659").isEmpty)
    }

    @Test("Coming back to the app inside a minute does not ask again; a forced refresh does")
    func spacing() async {
        let clock = TestClock(observed.addingTimeInterval(600))
        let server = StubServer { _ in .json(200, apiExample) }
        let store = store(server, clock: clock)
        await store.refresh()
        clock.advance(30)
        await store.refresh()
        #expect(server.requests.count == 1)
        await store.refresh(force: true)
        #expect(server.requests.count == 2)
        clock.advance(61)
        await store.refresh()
        #expect(server.requests.count == 3)
    }

    @Test("The hot-day flag follows the visible weather only")
    func hotFlag() async {
        let clock = TestClock(observed.addingTimeInterval(600))
        let hotText = apiExample.replacingOccurrences(of: "\"apparentTemperatureC\": 26.3", with: "\"apparentTemperatureC\": 31.0")
        let server = StubServer { _ in .json(200, hotText) }
        let store = store(server, clock: clock)
        await store.refresh()
        #expect(store.isHot)
        clock.advance(4 * 3600)
        #expect(!store.isHot, "no weather on screen, no hot-day line")
    }

    @Test("A store with no server shows nothing and asks nothing")
    func noServer() async {
        let store = ConditionsStore(client: nil)
        await store.refresh()
        #expect(store.weather() == nil)
        #expect(store.notices(for: "1").isEmpty)
    }
}
