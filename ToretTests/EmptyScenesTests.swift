import Foundation
import Testing

@testable import Toret

/// The states the app draws instead of printing a bare sentence. The drawings are looked at,
/// not tested; what can be pinned is that every state has words, that the words exist in all
/// three languages, and that the right problem gets the right scene.
@Suite("Empty scenes")
struct EmptyScenesTests {
    @Test("Every drawn scene has a state, and every state has a title and a sentence")
    func everySceneHasWords() {
        let drawn = Set(EmptySceneKind.gallery.map(\.art))
        #expect(drawn == Set(EmptySceneArtKind.allCases))
        for kind in EmptySceneKind.gallery {
            #expect(!kind.title.isEmpty)
            #expect(!kind.sentence.isEmpty)
            #expect(kind.accessibilityText.contains(kind.title))
        }
    }

    @Test("No two scenes share a title")
    func titlesAreDistinct() {
        let titles = EmptySceneKind.gallery.map(\.title)
        #expect(Set(titles).count == titles.count)
    }

    @Test("A location problem maps to the scene that explains it, and a working fix to none")
    func locationMapping() {
        #expect(EmptySceneKind(location: .denied) == .locationOff)
        #expect(EmptySceneKind(location: .restricted) == .locationOff)
        #expect(EmptySceneKind(location: .outsideTurin(kilometres: 520)) == .outsideTurin(kilometres: 520))
        #expect(EmptySceneKind(location: .live) == nil)
        #expect(EmptySceneKind(location: .approximate) == nil)
        #expect(EmptySceneKind(location: .searching) == nil)
        #expect(EmptySceneKind(location: .asking) == nil)
    }

    @Test("Only the far-from-Turin scene prints a distance, and it carries the number")
    func distanceLabel() {
        let far = EmptySceneKind.outsideTurin(kilometres: 9_400)
        let label = far.distanceLabel
        #expect(label?.hasSuffix("km") == true)
        #expect(label?.contains("9") == true)
        for kind in EmptySceneKind.gallery where kind != far {
            #expect(kind.distanceLabel == nil)
        }
        #expect(far.title.contains("9"))
    }

    @Test("Only the street-route scene stands higher than the others")
    func ground() {
        for kind in EmptySceneArtKind.allCases {
            #expect(kind.groundY <= EmptySceneBox.ground)
            #expect(kind.groundY > 0)
            #expect(kind == .noStreetRoute ? kind.groundY < EmptySceneBox.ground : kind.groundY == EmptySceneBox.ground)
        }
    }
}

@Suite("Empty scene words in three languages")
struct EmptySceneLanguageTests {
    private func lproj(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    /// The Portuguese source strings the scenes use, with the English and Italian each must
    /// resolve to something other than the Portuguese.
    private static let keys = [
        "Salve as fontes do seu caminho",
        "Ainda não há relatos",
        "Abra uma fonte e conte como está a água.",
        "Nenhuma fonte encontrada",
        "Nenhuma fonte aqui",
        "Afaste o mapa para ver as mais próximas.",
        "Ir para a mais próxima",
        "Sem a sua posição",
        "Ative a localização em Ajustes para medir as distâncias a partir de você.",
        "Sem rota de ruas",
        "As fontes não carregaram",
    ]

    @Test("Every scene string is translated, not repeated", arguments: ["en", "it"])
    func translated(language: String) throws {
        let bundle = try lproj(language)
        for key in Self.keys {
            let value = bundle.localizedString(forKey: key, value: nil, table: nil)
            #expect(!value.isEmpty && value != key, "\(language): \(key)")
        }
    }

    @Test("The far-from-Turin title keeps its number in every language", arguments: ["pt-BR", "en", "it"])
    func farTitle(language: String) throws {
        let bundle = try lproj(language)
        let format = bundle.localizedString(forKey: "Você está a %@ km de Turim", value: nil, table: nil)
        #expect(format.contains("%@"))
        #expect(String(format: format, "9.400").contains("9.400"))
    }
}
