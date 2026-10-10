import Foundation

/// Numbers, distances and times in the reader's own conventions.
///
/// Every figure the app prints goes through here, never through a hard-coded
/// locale: Brazilians read 4,6 and 1,2 km, Italians read 4,6 and 1,2 km, and an
/// English reader gets 4.6 and 1.2 km. Distances stay metric in every language —
/// the fountains are in Italy, and a "0.3 mi" on a Turin street sign would be
/// wrong for everybody.
enum Formatting {
    /// A 1–5 rating, one decimal: "4,6" or "4.6".
    static func rating(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(locale))
    }

    /// A whole number, with the locale's grouping: "12 000" / "12.000" / "12,000".
    /// Metre figures pass `grouping: false`: "1 240 m" is a different number on a
    /// sign than "1240", and nobody writes 999 m with a separator.
    static func integer(
        _ value: Int, locale: Locale = .autoupdatingCurrent, grouping: Bool = true
    ) -> String {
        value.formatted(.number.grouping(grouping ? .automatic : .never).locale(locale))
    }

    /// "há 2 h" / "2 hr. ago" / "2 h fa", relative to `now`.
    static func relative(
        _ date: Date, to now: Date = .now, locale: Locale = .autoupdatingCurrent
    ) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .abbreviated
        formatter.locale = locale
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// The time of day the way the device is set to show it: "14:05" or "2:05 PM".
    static func clock(_ date: Date, locale: Locale = .autoupdatingCurrent) -> String {
        date.formatted(.dateTime.hour().minute().locale(locale))
    }
}

/// A distance as a figure and a unit: 84 → "84" "m", 1240 → "1,2" "km".
///
/// One family for every surface — rows, the compass, widgets, the Live Activity,
/// Siri — so the same walk never reads "1,2 km" in one place and "1,24 km" in
/// another. Always metric, whatever the language (see ``Formatting``).
enum DistanceFormat {
    /// The unit a distance is shown in: "m" under a kilometre, "km" from there.
    ///
    /// Chosen from the *target* of a count-up, not from the value passing through
    /// on the way, so the unit does not flicker while the figure runs.
    static func unit(for metres: Int) -> String { metres >= 1000 ? "km" : "m" }

    /// The figure alone, in `unit`: "84", "1,2", "12". Under ten kilometres it
    /// keeps one decimal where there is one, because 1,2 km and 1,9 km are
    /// different walks; from ten up the decimal is noise. A figure that rounds to
    /// ten ("9,96") reads "10", not "10,0".
    static func figure(
        _ metres: Int, unit: String, locale: Locale = .autoupdatingCurrent
    ) -> String {
        guard unit == "km" else { return Formatting.integer(max(0, metres), locale: locale, grouping: false) }
        let kilometres = Double(max(0, metres)) / 1000
        if kilometres >= 9.95 {
            return kilometres.formatted(.number.precision(.fractionLength(0)).locale(locale))
        }
        return kilometres.formatted(.number.precision(.fractionLength(0 ... 1)).locale(locale))
    }

    static func parts(
        _ metres: Int, locale: Locale = .autoupdatingCurrent
    ) -> (value: String, unit: String) {
        let unit = unit(for: metres)
        return (figure(metres, unit: unit, locale: locale), unit)
    }

    /// "84 m", "1,2 km".
    static func short(_ metres: Int, locale: Locale = .autoupdatingCurrent) -> String {
        let parts = parts(metres, locale: locale)
        return "\(parts.value) \(parts.unit)"
    }

    /// For a voice: "84 metros", "1,2 quilômetros". The unit is a word in the
    /// reader's language, with its own plural ("1 metre", "84 metres", "1 metro",
    /// "84 metri").
    static func spoken(_ metres: Int, locale: Locale = .autoupdatingCurrent) -> String {
        let metres = max(0, metres)
        guard metres >= 1000 else { return String(localized: "\(metres) metros") }
        let value = figure(metres, unit: "km", locale: locale)
        let kilometres = Double(metres) / 1000
        // One kilometre, to the nearest tenth, is "1 quilômetro" and not "1 quilômetros".
        if (kilometres * 10).rounded() == 10 { return String(localized: "1 quilômetro") }
        return String(localized: "\(value) quilômetros")
    }
}
