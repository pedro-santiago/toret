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
                    .padding(.top, 14)
                }

                footer
                    .padding(.horizontal, 22)
                    .padding(.top, 30)
            }
            .padding(.bottom, Screen.tabBarClearance + 24)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .bottom)
        .background(Palette.paper)
        .refreshable { await community.refresh() }
        .task { await community.refresh() }
        .animation(Motion.ui, value: community.feed)
        .sheet(isPresented: $showingBlocked) { BlockedAuthorsSheet() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: String(localized: "Comunidade"))
            DisplayText("Relatos", size: 40, leading: 1, tracking: Typo.tracking(-0.015, at: 40))
                .padding(.top, 8)
            Text(subtitle)
                .font(Typo.ui(13.5))
                .foregroundStyle(Palette.ink.opacity(0.6))
                .padding(.top, 8)
            LozengeTicks().padding(.top, 16)
        }
        .padding(.top, 12)
    }

    private var subtitle: String {
        if community.feed.isEmpty { return String(localized: "Nada por aqui ainda") }
        return community.feed.count == 1
            ? String(localized: "1 relato nos últimos 30 dias")
            : String(localized: "\(community.feed.count) relatos nos últimos 30 dias")
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            StateGlyph(state: .unknown, size: 30)
            Text("Ainda não há relatos. Abra uma fonte e conte como está a água.")
                .font(Typo.ui(14))
                .foregroundStyle(Palette.ink.opacity(0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            if community.lastRefreshFailed {
                Text("Sem conexão no momento.")
                    .font(Typo.ui(12.5, 600))
                    .foregroundStyle(Palette.ink.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(CommunityNotice.text(for: community.availability, failed: community.lastRefreshFailed))
                .font(Typo.ui(12))
                .lineHeight(1.5, font: Typo.uiInterface(12))
                .foregroundStyle(Palette.ink.opacity(0.55))

            Text("Para denunciar um relato, use o menu ⋯ dele. Para qualquer outra coisa: contato@pedrosantiago.com.br")
                .font(Typo.ui(12))
                .lineHeight(1.5, font: Typo.uiInterface(12))
                .foregroundStyle(Palette.ink.opacity(0.55))

            if !community.blockedAuthors.isEmpty {
                Button(String(localized: "Autores bloqueados (\(community.blockedAuthors.count))")) {
                    showingBlocked = true
                }
                .font(Typo.ui(13, 600))
                .foregroundStyle(Palette.green)
            }
        }
    }
}

/// The people the user blocked, each with a way back.
struct BlockedAuthorsSheet: View {
    @Environment(Community.self) private var community
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: String(localized: "Comunidade"))
            DisplayText("Bloqueados", size: 30, leading: 1.05)
                .padding(.top, 6)

            if community.blockedAuthors.isEmpty {
                Text("Ninguém bloqueado.")
                    .font(Typo.ui(14))
                    .foregroundStyle(Palette.ink.opacity(0.55))
                    .padding(.top, 20)
            } else {
                ForEach(community.blockedAuthors, id: \.self) { author in
                    HStack {
                        Text(author)
                            .font(Typo.ui(15, 500))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Button(String(localized: "Desbloquear")) { community.unblock(author: author) }
                            .font(Typo.ui(13.5, 600))
                            .foregroundStyle(Palette.green)
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Palette.ink.opacity(0.08)).frame(height: 1)
                    }
                }
                .padding(.top, 14)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.paper)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
