import AppIntents
import Foundation

/// Opens the compass on the nearest fountain.
///
/// Shared between the app (Siri, Shortcuts, Spotlight) and the widget extension
/// (Control Center, the Lock Screen, the Action Button). It does nothing but hand
/// a `toret://` URL to the system: the app owns what that means, and measures the
/// *nearest* only once it has a fix of its own.
struct OpenCompassIntent: AppIntent {
    static let title: LocalizedStringResource = "Abrir a bússola"
    static let description = IntentDescription(
        "Abre a bússola do Toret apontando para a fonte mais próxima."
    )

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(DeepLink.compass(nearest: true).url))
    }
}

/// Starts the walk to the nearest fountain.
struct RouteToNearestIntent: AppIntent {
    static let title: LocalizedStringResource = "Traçar rota até a fonte mais próxima"
    static let description = IntentDescription(
        "Abre o Toret já com a rota a pé até a fonte mais próxima."
    )

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(DeepLink.routeToNearest.url))
    }
}
