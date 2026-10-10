import AppIntents
import WidgetKit

/// "Qual a fonte mais próxima?" — answered without opening the app.
///
/// Siri, Spotlight, Shortcuts and the Action Button all land here. It asks for one
/// fix, measures the catalogue from it and speaks the result; if the user has not
/// allowed location it says so and measures from the old town instead of guessing.
struct NearestFountainIntent: AppIntent {
    static let title: LocalizedStringResource = "Fonte mais próxima"
    static let description = IntentDescription(
        "Diz qual é a fonte de água mais próxima, a que distância e para que lado.",
        categoryName: "Água"
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let reading = await Self.reading(source: .nearest)
        let answer = SpokenAnswer.nearest(reading)
        return .result(value: answer, dialog: IntentDialog(stringLiteral: answer))
    }

    /// One fix, one catalogue pass.
    @MainActor
    static func reading(source: FountainSource) async -> WidgetReading {
        let result = await OneShotLocation.fetch(for: .app)
        let resolution = FixResolver.resolve(
            own: result.fix, bridged: WidgetBridge.origin(), denied: result.denied
        )
        return WidgetReading.make(
            source: source, saved: WidgetBridge.savedIDs(), resolution: resolution
        )
    }
}

/// Saves the fountain you are standing next to, by voice.
struct SaveNearestFountainIntent: AppIntent {
    static let title: LocalizedStringResource = "Salvar a fonte mais próxima"
    static let description = IntentDescription(
        "Guarda a fonte mais próxima nas suas salvas.",
        categoryName: "Água"
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reading = await NearestFountainIntent.reading(source: .nearest)
        // Saving "the nearest" from the old town because location was off would
        // save a fountain the user is not near — refuse rather than guess.
        guard reading.provenance.isMeasuringFromUser, let fountain = reading.featured else {
            return .result(dialog: "Preciso da sua localização para saber qual é a fonte mais próxima.")
        }

        var preferences = Preferences.load()
        guard preferences.savedIDs.insert(fountain.id).inserted else {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "\(fountain.place) já estava nas suas salvas.")))
        }
        preferences.save()
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "Salvei \(fountain.place).")))
    }
}

/// The phrases Siri and Spotlight listen for. Each has to name the app once.
struct ToretShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NearestFountainIntent(),
            phrases: [
                "Qual a fonte mais próxima no \(.applicationName)",
                "Onde tem água no \(.applicationName)",
                "Fonte de água perto de mim no \(.applicationName)",
                "Fonte mais próxima no \(.applicationName)",
            ],
            shortTitle: "Fonte mais próxima",
            systemImageName: "drop"
        )
        AppShortcut(
            intent: OpenCompassIntent(),
            phrases: [
                "Abrir a bússola do \(.applicationName)",
                "Bússola do \(.applicationName)",
            ],
            shortTitle: "Abrir a bússola",
            systemImageName: "location.north.line"
        )
        AppShortcut(
            intent: RouteToNearestIntent(),
            phrases: [
                "Me leve até a fonte mais próxima com o \(.applicationName)",
                "Traçar rota até a fonte no \(.applicationName)",
            ],
            shortTitle: "Rota até a fonte",
            systemImageName: "figure.walk"
        )
        AppShortcut(
            intent: SaveNearestFountainIntent(),
            phrases: [
                "Salvar a fonte mais próxima no \(.applicationName)",
            ],
            shortTitle: "Salvar a fonte",
            systemImageName: "diamond"
        )
    }
}
