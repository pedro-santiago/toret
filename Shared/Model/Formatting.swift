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
    static func integer(_ value: Int, locale: Locale = .autoupdatingCurrent) -> String {
        value.formatted(.number.locale(locale))
    }

    /// Metres under a kilometre, kilometres with one decimal above: "84 m", "1,2 km".
    static func distance(metres: Int, locale: Locale = .autoupdatingCurrent) -> String {
        let measurement: Measurement<UnitLength> = metres < 1000
            ? .init(value: Double(metres), unit: .meters)
            : .init(value: Double(metres) / 1000, unit: .kilometers)
        return measurement.formatted(
            .measurement(
                width: .abbreviated, usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(0 ... (metres < 1000 ? 0 : 1)))
            ).locale(locale)
        )
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
