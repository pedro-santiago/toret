import SwiftUI

/// What the Perto header says, kept apart from the view so it can be tested.
///
/// The sentence has one job: say how many fountains are within reach *and from
/// where the distances are measured*. A header that said "Torino, centro" or
/// "atualizado às 22:38" without being true of the fix on screen would put a
/// plausible, wrong claim over the one number the app exists to give.
enum NearbyCopy {
    /// Rows added each time "Ver mais" is pressed.
    static let pageSize = 8
    /// No list of nearby fountains needs to go past this.
    static let maximumRows = 80

    static func headline(within500: Int, nearest: Int?, fromUser: Bool) -> String {
        let anchor = String(localized: "Piazza San Carlo")
        let reference = fromUser
            ? String(localized: "de você")
            : String(localized: "da \(anchor)")
        if within500 == 1 { return String(localized: "1 fonte a até 500 m \(reference).") }
        if within500 > 1 { return String(localized: "\(within500) fontes a até 500 m \(reference).") }
        guard let nearest else { return String(localized: "O catálogo de fontes não carregou.") }
        return String(
            localized: "Nenhuma fonte a até 500 m \(reference). A mais próxima está a \(Distance.text(nearest))."
        )
    }
}

/// Perto — the same fountains as the map, sorted by the only thing that decides
/// anything on foot.
///
/// The title is the poster's: two syllables stacked, with the sun half off the
/// edge behind them. Under it, one sentence about where you are measured from,
/// the four shapes explained once, and then the list.
struct NearbyScreen: View {
    @Environment(ToretModel.self) private var model
    @Environment(LocationProvider.self) private var location

    @State private var visibleCount = NearbyCopy.pageSize

    private static let entranceKey = "nearby"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 22)

                LocationBanner(status: location.status)
                    .padding(.horizontal, 22)
                    .padding(.top, 18)

                PosterRule(weight: .heavy)
                    .padding(.top, 22)

                list

                if visibleCount < min(model.fountains.count, NearbyCopy.maximumRows) {
                    SecondaryButton(title: String(localized: "Ver mais fontes")) {
                        withAnimation(ScreenMotion.morph) {
                            visibleCount = min(visibleCount + NearbyCopy.pageSize, NearbyCopy.maximumRows)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 22)
                    .sensoryFeedback(.impact(weight: .light), trigger: visibleCount)
                }
            }
            .padding(.bottom, Screen.tabBarClearance + 120)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .bottom) { seeOnMap }
        .background(Palette.carta)
        .marksEntrancePlayed(key: Self.entranceKey)
        .animation(ScreenMotion.morph, value: location.status)
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .topLeading) {
            // The poster's sun, half off the right edge. It sits behind the title
            // and stays clear of the legend, where a yellow mark would vanish.
            SunDisc()
                .frame(width: 232, height: 232)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(x: 110, y: -34)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 18) {
                PosterTitle("PER", "TO", size: 104)
                    .padding(.top, 14)

                Text(headline)
                    .font(Typo.ui(17, 500))
                    .lineHeight(1.35, font: Typo.uiInterface(17, 500))
                    .foregroundStyle(Palette.inchiostro)
                    .fixedSize(horizontal: false, vertical: true)

                StateLegend()
            }
        }
    }

    private var headline: String {
        NearbyCopy.headline(
            within500: model.withinHalfKilometre,
            nearest: model.fountains.first?.distance,
            fromUser: location.status.isMeasuringFromUser
        )
    }

    // MARK: Rows

    private var list: some View {
        LazyVStack(spacing: 0) {
            let shown = Array(model.fountains.prefix(visibleCount))
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, fountain in
                FountainRow(
                    fountain: fountain,
                    isSelected: fountain == model.selected,
                    isDimmed: !model.matchesFilters(fountain)
                ) {
                    model.select(fountain)
                    model.push(.detail(fountain), in: .nearby)
                }
                .staggeredEntrance(key: Self.entranceKey, index: index)
            }
        }
    }

    // MARK: Pinned action

    private var seeOnMap: some View {
        VStack(spacing: 0) {
            PosterRule(weight: .heavy)
            PrimaryButton(title: String(localized: "Ver no mapa"), height: 52, fontSize: 18) {
                model.popToRoot(.nearby)
                model.tab = .map
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, Screen.tabBarClearance + 12)
        }
        // Opaque, all the way down behind the tab bar: a row sliding under the
        // button is cut off by the plate, not faded into it.
        .background(Palette.carta)
        .ignoresSafeArea(edges: .bottom)
    }
}

/// Salvas — the fountains a resident walks past every day.
///
/// Someone who does not need a map of the centre, only the few fountains on their
/// own route and how far each is from where they stand now.
struct SavedScreen: View {
    @Environment(ToretModel.self) private var model
    @Environment(LocationProvider.self) private var location

    private static let entranceKey = "saved"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 22)

                LocationBanner(status: location.status)
                    .padding(.horizontal, 22)
                    .padding(.top, 18)

                PosterRule(weight: .heavy)
                    .padding(.top, 22)

                if model.savedFountains.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .padding(.bottom, Screen.tabBarClearance + 24)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .bottom)
        .background(Palette.carta)
        .marksEntrancePlayed(key: Self.entranceKey)
        .sensoryFeedback(.impact(weight: .light), trigger: model.savedIDs.count)
        .animation(ScreenMotion.morph, value: model.savedIDs)
    }

    private var header: some View {
        ZStack(alignment: .topLeading) {
            // The chequered diamond, partly off the edge: the poster's other
            // geometric hero, standing in for the sun on this screen.
            DiamondChecker()
                .frame(width: 210, height: 210)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(x: 66, y: -16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 18) {
                PosterTitle("SAL", "VAS", size: 104)
                    .padding(.top, 14)

                Text(sentence)
                    .font(Typo.ui(17, 500))
                    .lineHeight(1.35, font: Typo.uiInterface(17, 500))
                    .foregroundStyle(Palette.inchiostro)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sentence: String {
        let count = model.savedFountains.count
        switch count {
        case 0: return String(localized: "Você ainda não salvou nenhuma fonte.")
        case 1: return String(localized: "1 fonte no seu trajeto.")
        default: return String(localized: "\(count) fontes no seu trajeto, da mais próxima à mais distante.")
        }
    }

    private var list: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(model.savedFountains.enumerated()), id: \.element.id) { index, fountain in
                FountainRow(fountain: fountain, isSelected: fountain == model.selected) {
                    model.select(fountain)
                    model.push(.detail(fountain), in: .saved)
                }
                .staggeredEntrance(key: Self.entranceKey, index: index)
                .contextMenu {
                    Button(String(localized: "Traçar rota")) { model.walkingTo = fountain }
                    Button(String(localized: "Remover das salvas"), role: .destructive) {
                        model.toggleSaved(fountain)
                    }
                }
            }
        }
    }

    /// An empty list is an invitation: say what it is for, then give the way in.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(String(localized: "Salve as fontes do seu caminho"))
                .font(Typo.display(30, 800))
                .lineHeight(1.0, font: Typo.uiDisplay(30, 800))
                .foregroundStyle(Palette.inchiostro)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(localized: "Abra uma fonte e toque em salvar. Ela aparece aqui, com a distância de onde você está agora."))
                .font(Typo.ui(16))
                .lineHeight(1.4, font: Typo.uiInterface(16))
                .foregroundStyle(Palette.ink(0.78))
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: String(localized: "Encontrar fontes"), height: 56, fontSize: 18) {
                model.tab = .nearby
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 28)
    }
}
