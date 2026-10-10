import Foundation
import Testing

@testable import Toret

// MARK: - Which language the app picks

/// A device in German must get English, not the Portuguese the source strings are
/// written in; a device in Portugal must get Portuguese, and Swiss Italian must
/// get Italian. These rest on `CFBundleDevelopmentRegion` and `CFBundleLocalizations`
/// in project.yml, so a regenerated project that loses them fails here.
@Suite("Language selection")
struct LanguageSelectionTests {
    @Test("The bundle declares pt-BR, English and Italian, with English as the fallback")
    func declared() {
        #expect(Bundle.main.developmentLocalization == "en")
        for language in ["pt-BR", "en", "it"] {
            #expect(Bundle.main.localizations.contains(language), "missing \(language)")
        }
    }

    @Test("Device languages resolve to the right translation", arguments: [
        (["de"], "en"), (["es-419"], "en"), (["zh-Hans"], "en"), (["en-GB"], "en"),
        (["pt-PT"], "pt-BR"), (["pt-BR"], "pt-BR"), (["it"], "it"), (["it-CH"], "it"),
        (["fr", "it"], "it"), (["de", "pt-PT"], "pt-BR"),
    ] as [([String], String)])
    func resolves(preferences: [String], expected: String) {
        let chosen = Bundle.preferredLocalizations(
            from: Bundle.main.localizations.filter { $0 != "Base" }, forPreferences: preferences
        )
        #expect(chosen.first == expected)
    }
}

// MARK: - The catalogs

private struct Catalogs {
    /// The repository root, found from this file: tests run on the host's file
    /// system in the simulator.
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()

    static func load(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent(path))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// printf conversions (`%@`, `%lld`, `%1$@`...), as a sorted list of their types.
    static func specifiers(_ text: String) -> [String] {
        let pattern = #"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?([@dDiuUxXoOfeEgGcCsSpaA])"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let cleaned = text.replacingOccurrences(of: "%%", with: "")
        return regex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
            .compactMap { Range($0.range(at: 1), in: cleaned).map { String(cleaned[$0]).lowercased() } }
            .sorted()
    }
}

@Suite("String catalogs")
struct CatalogTests {
    private static let languages = ["pt-BR", "en", "it"]

    private func entries(_ path: String) throws -> [String: [String: Any]] {
        try #require(try Catalogs.load(path)["strings"] as? [String: [String: Any]])
    }

    @Test("Every key is translated into every language, and nothing is left half-done")
    func complete() throws {
        for path in ["Shared/Resources/Localizable.xcstrings", "Toret/Resources/InfoPlist.xcstrings"] {
            let catalog = try Catalogs.load(path)
            let source = catalog["sourceLanguage"] as? String
            for (key, entry) in try entries(path) {
                #expect(entry["extractionState"] as? String != "stale", "\(key) is stale")
                let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
                for language in Self.languages where language != source {
                    #expect(localizations[language] != nil, "\(key) lacks \(language)")
                }
                for (language, localization) in localizations {
                    var units: [[String: Any]] = []
                    if let unit = localization["stringUnit"] as? [String: Any] { units.append(unit) }
                    let plural = (localization["variations"] as? [String: Any])?["plural"] as? [String: [String: Any]]
                    units += plural?.values.compactMap { $0["stringUnit"] as? [String: Any] } ?? []
                    for unit in units {
                        #expect(unit["state"] as? String == "translated", "\(key) [\(language)] is \(unit["state"] ?? "?")")
                        #expect(!((unit["value"] as? String) ?? "").isEmpty, "\(key) [\(language)] is empty")
                    }
                }
            }
        }
    }

    /// A translation that drops or adds a `%@` crashes `String(format:)` or prints
    /// the wrong number. Positional specifiers may reorder, never change.
    @Test("Every translation keeps the source's format specifiers")
    func specifiers() throws {
        for (key, entry) in try entries("Shared/Resources/Localizable.xcstrings") {
            let expected = Catalogs.specifiers(key)
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            for (language, localization) in localizations {
                var values: [String] = []
                if let unit = localization["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
                    values.append(value)
                }
                let plural = (localization["variations"] as? [String: Any])?["plural"] as? [String: [String: Any]]
                values += plural?.values.compactMap { ($0["stringUnit"] as? [String: Any])?["value"] as? String } ?? []
                for value in values {
                    #expect(Catalogs.specifiers(value) == expected, "\(key) [\(language)]: \(value)")
                }
            }
        }
    }

    @Test("Siri phrases exist in every language and each one names the app")
    func shortcuts() throws {
        for (key, entry) in try entries("Toret/Resources/AppShortcuts.xcstrings") {
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            for language in Self.languages {
                let phrases = (localizations[language]?["stringSet"] as? [String: Any])?["values"] as? [String]
                #expect(phrases?.isEmpty == false, "\(key) lacks \(language)")
                for phrase in phrases ?? [] {
                    #expect(phrase.contains("${applicationName}"), "\(phrase) does not name the app")
                }
            }
        }
    }
}

// MARK: - What the compiled bundle says

@Suite("Compiled translations")
struct CompiledTranslationTests {
    private func lproj(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test("The three languages say the same thing in their own words", arguments: [
        ("Água corrente", "pt-BR", "Água corrente"),
        ("Água corrente", "en", "Water running"),
        ("Água corrente", "it", "Acqua che scorre"),
        ("Sem relato recente", "en", "No recent report"),
        ("Sem relato recente", "it", "Nessuna segnalazione recente"),
        ("Turim", "en", "Turin"),
        ("Turim", "it", "Torino"),
    ])
    func labels(key: String, language: String, expected: String) throws {
        let bundle = try lproj(language)
        #expect(bundle.localizedString(forKey: key, value: nil, table: nil) == expected)
    }

    /// Plural rules live in the generated .stringsdict: Xcode compiles a catalog's
    /// plural variations into one table per language, with a `value` rule holding
    /// one text per category. English, Portuguese and Italian all use `one` for 1.
    @Test("Plurals use each language's own noun", arguments: [
        ("pt-BR", 1, "1 avaliação"), ("pt-BR", 3, "3 avaliações"),
        ("en", 1, "1 rating"), ("en", 2, "2 ratings"),
        ("it", 1, "1 valutazione"), ("it", 5, "5 valutazioni"),
    ])
    func plurals(language: String, count: Int, expected: String) throws {
        let url = try #require(try lproj(language).url(forResource: "Localizable", withExtension: "stringsdict"))
        let table = try #require(NSDictionary(contentsOf: url) as? [String: Any])
        let entry = try #require(table["%lld avaliações"] as? [String: Any])
        let rule = try #require(entry["value"] as? [String: Any])
        let format = try #require(rule[count == 1 ? "one" : "other"] as? String)
        #expect(String(format: format, count) == expected)
    }

    @Test("Metres have their own plural in every language", arguments: [
        ("pt-BR", 1, "1 metro"), ("pt-BR", 84, "84 metros"),
        ("en", 1, "1 meter"), ("en", 84, "84 meters"),
        ("it", 1, "1 metro"), ("it", 84, "84 metri"),
    ])
    func metres(language: String, count: Int, expected: String) throws {
        let url = try #require(try lproj(language).url(forResource: "Localizable", withExtension: "stringsdict"))
        let table = try #require(NSDictionary(contentsOf: url) as? [String: Any])
        let entry = try #require(table["%lld metros"] as? [String: Any])
        let rule = try #require(entry["value"] as? [String: Any])
        let format = try #require(rule[count == 1 ? "one" : "other"] as? String)
        #expect(String(format: format, count) == expected)
    }
}

// MARK: - Formatting

@Suite("Formatting")
struct FormattingTests {
    private let portuguese = Locale(identifier: "pt_BR")
    private let english = Locale(identifier: "en_US")
    private let italian = Locale(identifier: "it_IT")

    @Test("A rating uses the reader's decimal separator")
    func rating() {
        #expect(Formatting.rating(4.56, locale: portuguese) == "4,6")
        #expect(Formatting.rating(4.56, locale: italian) == "4,6")
        #expect(Formatting.rating(4.56, locale: english) == "4.6")
    }

    /// The fountains are in Italy: an American reader still gets metres.
    @Test("Distances stay metric in every language")
    func distance() {
        #expect(DistanceFormat.short(84, locale: english) == "84 m")
        #expect(DistanceFormat.short(84, locale: italian) == "84 m")
        #expect(DistanceFormat.short(1234, locale: english) == "1.2 km")
        #expect(DistanceFormat.short(1234, locale: italian) == "1,2 km")
        #expect(DistanceFormat.short(1234, locale: portuguese) == "1,2 km")
        #expect(DistanceFormat.short(1000, locale: english) == "1 km")
        #expect(DistanceFormat.short(12_400, locale: english) == "12 km")
        for locale in [english, italian, portuguese] {
            let text = DistanceFormat.short(5000, locale: locale)
            #expect(!text.contains("mi") && !text.contains("ft"))
        }
    }

    /// 9,96 km rounds to ten: it reads "10", not "10,0".
    @Test("A figure that rounds to ten has no decimal")
    func roundsToTen() {
        #expect(DistanceFormat.figure(9960, unit: "km", locale: portuguese) == "10")
        #expect(DistanceFormat.figure(9940, unit: "km", locale: portuguese) == "9,9")
    }

    /// Metres are a plain figure: "1 240 m" on a sign is a different number.
    @Test("Metre figures carry no grouping separator")
    func noGrouping() {
        #expect(DistanceFormat.figure(999, unit: "m", locale: english) == "999")
        #expect(Formatting.integer(1240, locale: english, grouping: false) == "1240")
        #expect(Formatting.integer(1240, locale: english) == "1,240")
    }

    @Test("Relative times read naturally in each language")
    func relative() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let twoHoursAgo = now.addingTimeInterval(-2 * 3600)
        #expect(Formatting.relative(twoHoursAgo, to: now, locale: portuguese).contains("há"))
        #expect(Formatting.relative(twoHoursAgo, to: now, locale: english).contains("ago"))
        #expect(Formatting.relative(twoHoursAgo, to: now, locale: italian).contains("fa"))
    }

    @Test("The clock follows the locale's 12 or 24 hour habit")
    func clock() {
        let noonish = Calendar(identifier: .gregorian).date(
            from: DateComponents(timeZone: .gmt, year: 2026, month: 10, day: 10, hour: 14, minute: 5)
        )!
        // Formatting uses the device time zone, so compare shapes rather than hours.
        #expect(Formatting.clock(noonish, locale: english).contains("M"))
        #expect(!Formatting.clock(noonish, locale: italian).contains("M"))
    }
}

// MARK: - Model strings

@Suite("Model strings")
struct ModelStringTests {
    /// The chips are stored by key, not by what they say: a build in another
    /// language, or a later rewording, must not lose anyone's choice. Builds before
    /// the translation stored the Portuguese title.
    @Test("Filters are stored by a stable key and still read the old titles")
    func filterStorage() {
        #expect(MapFilter.accessible.rawValue == "accessible")
        for filter in MapFilter.allCases {
            #expect(MapFilter(stored: filter.rawValue) == filter)
        }
        #expect(MapFilter(stored: "Sem relato de seca") == .notDry)
        #expect(MapFilter(stored: "Acessível") == .accessible)
        #expect(MapFilter(stored: "Para garrafa") == .bottle)
        #expect(MapFilter(stored: "Para cães") == .dogs)
        #expect(MapFilter(stored: "Com água") == nil)
        #expect(MapFilter(stored: "Aberta 24 h") == nil)
    }

    @Test("Every chip has a title")
    func filterTitles() {
        for filter in MapFilter.allCases {
            #expect(!filter.title.isEmpty)
        }
    }

    /// Mappers write the kind of thing in the name field when they have nothing to
    /// say, in whichever language they think in.
    @Test("Generic names in any language give way to the street", arguments: [
        "Fontanella", "FONTANA", "Acqua potabile", "Drinking Water", "water fountain",
        "Água potável", "Fonte", "  toret  ",
    ])
    func genericNames(name: String) {
        let entry = CatalogueEntry(
            id: "1", lat: 45.07, lon: 7.68, kind: .fountain, name: name,
            street: "Via Po", zone: "Centro", ref: nil, wheelchair: nil, bottle: nil,
            dog: nil, seasonal: nil, checked: nil
        )
        #expect(Fountain(entry: entry, from: Catalogue.anchor).place == "Via Po")
    }

    @Test("A real name is kept")
    func realName() {
        let entry = CatalogueEntry(
            id: "1", lat: 45.07, lon: 7.68, kind: .fountain, name: "Fontana dei Dodici Mesi",
            street: "Parco del Valentino", zone: nil, ref: nil, wheelchair: nil, bottle: nil,
            dog: nil, seasonal: nil, checked: nil
        )
        #expect(Fountain(entry: entry, from: Catalogue.anchor).place == "Fontana dei Dodici Mesi")
    }

    @Test("Every state, kind and tag has a label")
    func labels() {
        for state in WaterState.allCases {
            #expect(!state.label.isEmpty && !state.shortLabel.isEmpty)
        }
        for tag in ReportTag.allCases { #expect(!tag.label.isEmpty) }
        for access in [WheelchairAccess.yes, .limited, .no] { #expect(!access.label.isEmpty) }
        for kind in [FountainKind.toret, .fountain, .bubbler, .refill] { #expect(!kind.label.isEmpty) }
    }
}
