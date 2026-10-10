import AppIntents
import WidgetKit

/// What the widget follows: the nearest fountain, or the nearest of the ones the
/// user saved.
extension FountainSource: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Fontes"
    static let caseDisplayRepresentations: [FountainSource: DisplayRepresentation] = [
        .nearest: "Mais próxima",
        .saved: "Minhas salvas",
    ]
}

/// The widget's one setting, reachable by long-pressing it.
struct FountainSelectionIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Fonte"
    static let description = IntentDescription(
        "Escolha entre a fonte mais próxima e a mais próxima entre as que você salvou."
    )

    @Parameter(title: "Mostrar", default: .nearest)
    var source: FountainSource

    init() {}

    init(source: FountainSource) {
        self.source = source
    }
}
