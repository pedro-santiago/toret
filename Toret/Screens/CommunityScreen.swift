import SwiftUI

/// Relatos — what people are saying about the city's fountains, newest first.
///
/// The feed behind the tab. Each row says which fountain it is about and how far
/// away it is, and opens that fountain; the bottom of the page says who to write
/// to about anything offensive, and lets the user undo a block.
struct CommunityScreen: View {
    @Environment(ToretModel.self) private var model
    @Environment(Community.self) private var community
    @State private var showingBlocked = false

    var body: some View {
        let fountains = Dictionary(
            model.fountains.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 22)

                if community.feed.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(community.feed) { report in
                            if let fountain = fountains[report.fountainID] {
                                ReportRow(report: report, fountain: fountain) {
                                    model.select(fountain)
                                    model.push(.detail(fountain), in: .community)
                                }
                                .padding(.horizontal, 22)
                            }
                        }
                    }
                    .overlay(alignment: .top) { PosterRule().padding(.horizontal, 22) }
                    .padding(.top, 22)
                }

                footer
                    .padding(.horizontal, 22)
                    .padding(.top, 30)
            }
            .padding(.bottom, Screen.tabBarClearance + 24)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .bottom)
        .background(Palette.carta)
        .refreshable { await community.refresh() }
        .task { await community.refresh() }
        .animation(Motion.ui, value: community.feed)
        .sheet(isPresented: $showingBlocked) { BlockedAuthorsSheet() }
    }

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            // The Mole at the trailing edge, small, as a monument beside the title. It leans
            // with the phone and nothing else about this screen moves.
            TiltedParallaxScene(
                layers: [.mole], flowing: false,
                window: CGRect(x: 480, y: 0, width: 440, height: PosterSceneGeometry.moleBase)
            )
            .frame(width: 104)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                PosterTitle(localized: "RELA\nTOS")
                    .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in width * 0.66 }
                Text(subtitle)
                    .font(Typo.ui(16))
                    .foregroundStyle(Palette.inchiostro)
                    .padding(.top, 14)
            }
        }
        .padding(.top, 12)
    }

    private var subtitle: String {
        if community.feed.isEmpty { return String(localized: "Nada por aqui ainda.") }
        return community.feed.count == 1
            ? String(localized: "1 relato nos últimos 30 dias.")
            : String(localized: "\(community.feed.count) relatos nos últimos 30 dias.")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            EmptyScene(
                kind: .feed,
                actionTitle: String(localized: "Encontrar fontes")
            ) {
                model.tab = .nearby
            }
            if community.lastRefreshFailed {
                Text("Sem conexão no momento.")
                    .font(Typo.ui(14, 700))
                    .foregroundStyle(Palette.inchiostro)
                    .padding(.horizontal, 22)
            }
        }
        .padding(.top, 28)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            PosterRule()
            Text(CommunityNotice.text(for: community.availability, failed: community.lastRefreshFailed))
                .font(Typo.ui(14))
                .foregroundStyle(Palette.inchiostro.opacity(0.7))

            Text("Para denunciar um relato, use o menu de três pontos dele. Para qualquer outra coisa, escreva para:")
                .font(Typo.ui(14))
                .foregroundStyle(Palette.inchiostro.opacity(0.7))
            if let mail = URL(string: "mailto:contato@pedrosantiago.com.br") {
                Link("contato@pedrosantiago.com.br", destination: mail)
                    .font(Typo.ui(15, 700))
                    .foregroundStyle(Palette.blu)
                    .tint(Palette.blu)
            }

            if !community.blockedAuthors.isEmpty {
                Button(String(localized: "Autores bloqueados (\(community.blockedAuthors.count))")) {
                    showingBlocked = true
                }
                .font(Typo.ui(15, 700))
                .foregroundStyle(Palette.blu)
            }
        }
    }
}

/// The people the user blocked, each with a way back.
struct BlockedAuthorsSheet: View {
    @Environment(Community.self) private var community

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PosterTitle(localized: "BLO\nQUEIOS", size: 56)

            if community.blockedAuthors.isEmpty {
                Text("Ninguém bloqueado.")
                    .font(Typo.ui(16))
                    .foregroundStyle(Palette.inchiostro)
                    .padding(.top, 22)
            } else {
                VStack(spacing: 0) {
                    ForEach(community.blockedAuthors, id: \.self) { author in
                        HStack {
                            Text(author)
                                .font(Typo.ui(17, 700))
                                .foregroundStyle(Palette.inchiostro)
                            Spacer()
                            Button(String(localized: "Desbloquear")) { community.unblock(author: author) }
                                .font(Typo.ui(15, 700))
                                .foregroundStyle(Palette.blu)
                        }
                        .padding(.vertical, 14)
                        .overlay(alignment: .bottom) { PosterRule(weight: .light) }
                    }
                }
                .padding(.top, 22)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.carta)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
