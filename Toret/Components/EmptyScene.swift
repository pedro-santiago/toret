import SwiftUI

/// Which of the drawn scenes a screen is in, and what it says.
///
/// The drawing is `EmptySceneArtKind` in the shared design system; this adds the one thing
/// that varies in the copy (how far from Turin you are) and the words, so a test can say
/// "every state has a title and a sentence" without drawing anything.
enum EmptySceneKind: Equatable, Sendable {
    case saved
    case feed
    case noResults
    case noPins
    case locationOff
    case outsideTurin(kilometres: Int)
    case noStreetRoute
    case catalogueFailed

    /// One of each, for the gallery and the tests.
    static let gallery: [EmptySceneKind] = [
        .saved, .feed, .noResults, .noPins, .locationOff,
        .outsideTurin(kilometres: 9_400), .noStreetRoute, .catalogueFailed,
    ]

    var art: EmptySceneArtKind {
        switch self {
        case .saved: .saved
        case .feed: .feed
        case .noResults: .noResults
        case .noPins: .noPins
        case .locationOff: .locationOff
        case .outsideTurin: .outsideTurin
        case .noStreetRoute: .noStreetRoute
        case .catalogueFailed: .catalogueFailed
        }
    }

    /// The printed distance on the scene that has one.
    var distanceLabel: String? {
        guard case let .outsideTurin(kilometres) = self else { return nil }
        return "\(kilometres.formatted(.number)) km"
    }

    var title: String {
        switch self {
        case .saved: String(localized: "Salve as fontes do seu caminho")
        case .feed: String(localized: "Ainda não há relatos")
        case .noResults: String(localized: "Nenhuma fonte encontrada")
        case .noPins: String(localized: "Nenhuma fonte aqui")
        case .locationOff: String(localized: "Sem a sua posição")
        case let .outsideTurin(kilometres):
            String(localized: "Você está a \(kilometres.formatted(.number)) km de Turim")
        case .noStreetRoute: String(localized: "Sem rota de ruas")
        case .catalogueFailed: String(localized: "As fontes não carregaram")
        }
    }

    var sentence: String {
        switch self {
        case .saved:
            String(localized: "Abra uma fonte e toque em salvar. Ela aparece aqui, com a distância de onde você está agora.")
        case .feed:
            String(localized: "Abra uma fonte e conte como está a água.")
        case .noResults:
            String(localized: "Procure pelo nome de uma rua, de uma praça ou de um bairro.")
        case .noPins:
            String(localized: "Afaste o mapa para ver as mais próximas.")
        case .locationOff:
            String(localized: "Ative a localização em Ajustes para medir as distâncias a partir de você.")
        case .outsideTurin:
            String(localized: "As distâncias são medidas a partir da \(String(localized: "Piazza San Carlo")).")
        case .noStreetRoute:
            String(localized: "Siga na direção da fonte")
        case .catalogueFailed:
            String(localized: "A lista de fontes que vem com o app não pôde ser lida. Feche e abra o Toret de novo; se continuar, reinstale o app.")
        }
    }

    /// The label VoiceOver reads for the scene as a whole: the words, once.
    var accessibilityText: String { "\(title). \(sentence)" }
}

extension EmptySceneKind {
    /// The scene a location problem calls for, if it calls for one. Asking, searching, live and
    /// approximate are not empty states: the app is working, or about to.
    init?(location status: LocationStatus) {
        switch status {
        case .denied, .restricted: self = .locationOff
        case let .outsideTurin(kilometres): self = .outsideTurin(kilometres: kilometres)
        case .asking, .searching, .live, .approximate: return nil
        }
    }
}

/// A scene with its words: the drawing, a title, one plain sentence and, where the user can
/// do something about it, one black button.
///
/// `.page` is a whole screen's worth: the scene stands on a full-width river with the words
/// under it. `.row` is for a plate on a map, a drawer, a list: the scene small on the left
/// and the words beside it, no plate of its own (the caller supplies one).
struct EmptyScene: View {
    enum Layout { case page, row }

    /// How much bigger than its design box a page-sized scene is printed.
    static let pageScale: CGFloat = 1.4

    let kind: EmptySceneKind
    var layout: Layout = .page
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        switch layout {
        case .page: page
        case .row: row
        }
    }

    // MARK: Page

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The art is drawn small and printed bigger, so one stroke weight serves a notice
            // and a page alike; the river under it runs the full width of the screen.
            ZStack(alignment: .bottom) {
                RiverFoot().frame(height: (EmptySceneBox.height - kind.art.groundY) * Self.pageScale)
                EmptySceneArt(kind: kind.art, distanceLabel: kind.distanceLabel)
                    .scaleEffect(Self.pageScale, anchor: .topLeading)
                    .frame(
                        width: EmptySceneBox.width * Self.pageScale,
                        height: EmptySceneBox.height * Self.pageScale, alignment: .topLeading
                    )
                    .frame(maxWidth: .infinity)
            }
            .frame(height: EmptySceneBox.height * Self.pageScale)

            VStack(alignment: .leading, spacing: 14) {
                Text(kind.title)
                    .font(Typo.display(28, 800))
                    .lineHeight(1.0, font: Typo.uiDisplay(28, 800))
                    .foregroundStyle(Palette.inchiostro)
                    .fixedSize(horizontal: false, vertical: true)
                Text(kind.sentence)
                    .font(Typo.ui(16))
                    .lineHeight(1.4, font: Typo.uiInterface(16))
                    .foregroundStyle(Palette.ink(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    PrimaryButton(title: actionTitle, height: 56, fontSize: 18, action: action)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Row

    private var row: some View {
        HStack(alignment: .center, spacing: 14) {
            EmptySceneMini(kind: kind.art, height: 74, distanceLabel: kind.distanceLabel)
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.title)
                    .font(Typo.display(18, 800))
                    .foregroundStyle(Palette.inchiostro)
                    .fixedSize(horizontal: false, vertical: true)
                Text(kind.sentence)
                    .font(Typo.ui(13))
                    .foregroundStyle(Palette.ink(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(action: action) {
                        Text(actionTitle)
                            .font(Typo.display(14, 800))
                            .foregroundStyle(Palette.carta)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(Palette.inchiostro)
                    }
                    .buttonStyle(.pressable)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }
}

/// The river at the foot of a page-sized scene: the ground rule over blue bands, full width.
struct RiverFoot: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.inchiostro).frame(height: 3)
            RiverStripes(bands: 3)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Debug gallery

#if DEBUG
/// Every scene, one under the other, for looking at: `-toret-screen vazios`. With
/// `-toret-vazio 3` only the fourth, as a page and as a row, so one capture shows one scene.
struct EmptyGallery: View {
    private var only: Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-toret-vazio"), arguments.indices.contains(flag + 1)
        else { return nil }
        return Int(arguments[flag + 1])
    }

    var body: some View {
        let kinds = Array(EmptySceneKind.gallery.enumerated())
        let shown = kinds.filter { only == nil || $0.offset == only }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(shown, id: \.offset) { index, kind in
                    EmptyScene(
                        kind: kind,
                        actionTitle: index.isMultiple(of: 3) ? String(localized: "Encontrar fontes") : nil,
                        action: index.isMultiple(of: 3) ? {} : nil
                    )
                    .padding(.top, only == nil ? 28 : 70)
                    .padding(.bottom, 28)
                    PosterRule()
                }
                ForEach(shown, id: \.offset) { _, kind in
                    EmptyScene(kind: kind, layout: .row, actionTitle: String(localized: "Abrir Ajustes"), action: {})
                        .padding(12)
                        .plate()
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                }
            }
            .padding(.bottom, 60)
        }
        .background(Palette.carta)
    }
}

/// Presents the gallery as a full-screen cover, so the debug switch needs one line in RootView.
struct EmptyGalleryHook: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented) { EmptyGallery() }
    }
}
#else
struct EmptyGalleryHook: ViewModifier {
    @Binding var isPresented: Bool
    func body(content: Content) -> some View { content }
}
#endif
