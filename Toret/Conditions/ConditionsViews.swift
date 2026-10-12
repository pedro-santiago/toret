import SwiftUI

/// The words for the conditions, kept apart from the views so they can be tested.
///
/// Every sentence names its source and the time it was fetched, and none of them
/// says anything about the water in a fountain: weather and works orders are
/// context, "possibly affected" at most.
enum ConditionsCopy {
    private static let rome = TimeZone(identifier: "Europe/Rome") ?? .gmt

    /// "Turim agora: 21 °C, sensação 20 °C · Open-Meteo, 17:45", and on a hot day
    /// "Dia quente: leve água." after it. The time is when Open-Meteo took the reading.
    static func weatherLine(
        _ weather: Conditions.Weather, hot: Bool, locale: Locale = .autoupdatingCurrent
    ) -> String {
        let line = String(
            localized: "Turim agora: \(Self.degrees(weather.temperatureC)) °C, sensação \(Self.degrees(weather.apparentTemperatureC)) °C · Open-Meteo, \(Formatting.clock(weather.observedAt, locale: locale))"
        )
        return hot ? "\(line). \(hotDay)" : line
    }

    static var hotDay: String { String(localized: "Dia quente: leve água.") }

    /// What VoiceOver reads for the line: the figures with their unit spelled out.
    static func weatherSpoken(
        _ weather: Conditions.Weather, hot: Bool, locale: Locale = .autoupdatingCurrent
    ) -> String {
        let line = String(
            localized: "Turim agora: \(Self.degrees(weather.temperatureC)) graus, sensação térmica \(Self.degrees(weather.apparentTemperatureC)) graus. Fonte: Open-Meteo, \(Formatting.clock(weather.observedAt, locale: locale))."
        )
        return hot ? "\(line) \(hotDay)" : line
    }

    /// "A SMAT lista uma obra perto de Corso X, iniciada em 5 out 2026. O
    /// abastecimento próximo pode ser afetado. Fonte: SMAT, 15:05"
    static func worksNotice(_ notice: Conditions.Notice, locale: Locale = .autoupdatingCurrent) -> String {
        let started = startedOn(notice.startedOn, locale: locale) ?? notice.startedOn
        let time = Formatting.clock(notice.fetchedAt, locale: locale)
        return String(
            localized: "A SMAT lista uma obra perto de \(notice.street), iniciada em \(started). O abastecimento próximo pode ser afetado. Fonte: SMAT, \(time)"
        )
    }

    /// A rounded whole number; -0 reads "0".
    static func degrees(_ value: Double) -> Int {
        let rounded = Int(value.rounded())
        return rounded == 0 ? 0 : rounded
    }

    /// `2026-10-05` as "5 de out. de 2026" or "Oct 5, 2026": a calendar date in
    /// Europe/Rome, shown as the same day wherever the phone is.
    static func startedOn(_ text: String, locale: Locale = .autoupdatingCurrent) -> String? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = rome
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
        else { return nil }
        return date.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: rome).day().month(.abbreviated).year()
        )
    }
}

/// One quiet line under the cover of Perto: the weather in Turin, where it comes
/// from and when. Nothing at all when there is no recent reading, so the page
/// never shows a stale number or an empty slot.
struct WeatherLine: View {
    @Environment(ConditionsStore.self) private var store: ConditionsStore?

    var body: some View {
        if let store, let weather = store.weather() {
            let hot = store.isHot
            Text(ConditionsCopy.weatherLine(weather, hot: hot))
                .font(Typo.ui(13, 500))
                .lineHeight(1.35, font: Typo.uiInterface(13, 500))
                .foregroundStyle(Palette.inchiostro.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ConditionsCopy.weatherSpoken(weather, hot: hot))
        }
    }
}

/// SMAT's works orders that mention this fountain's street, as plain notes on
/// the fountain's page. They say what SMAT lists and from when; they never say
/// what the water is doing, and they have no shape or colour of a water state.
struct WorksNotices: View {
    let fountainID: String

    @Environment(ConditionsStore.self) private var store: ConditionsStore?

    var body: some View {
        if let store {
            ForEach(store.notices(for: fountainID)) { notice in
                Text(ConditionsCopy.worksNotice(notice))
                    .font(Typo.ui(14.5))
                    .lineHeight(1.45, font: Typo.uiInterface(14.5))
                    .foregroundStyle(Palette.inchiostro)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .plate(fill: Palette.cartaChiara, lineWidth: 2)
                    .accessibilityElement(children: .combine)
                    .padding(.top, 20)
            }
        }
    }
}

/// Keeps the conditions fresh while the app is in front: once when it comes
/// forward, then every 15 minutes. Leaving the foreground cancels the loop.
struct ConditionsHooks: ViewModifier {
    let store: ConditionsStore

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await store.run()
        }
    }
}
