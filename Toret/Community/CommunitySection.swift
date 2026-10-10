import SwiftUI

/// The community's word about one fountain: the rating, what people tend to say
/// about it, the latest reports, and the button that adds to them.
///
/// Sits under the "Comunidade" header on the detail screen. It reads the
/// community store for the fountain's own reports and refreshes them when it
/// appears, so a fountain opened from a notification is not stale.
struct CommunitySection: View {
    let fountain: Fountain

    @Environment(Community.self) private var community
    @State private var composing = false
    @State private var showingAll = false

    private static let preview = 3

    var body: some View {
        let reports = community.reports(for: fountain.id)
        let summary = community.summary(for: fountain.id)
        let shown = showingAll ? reports : Array(reports.prefix(Self.preview))

        VStack(alignment: .leading, spacing: 0) {
            header(summary)

            let tags = community.topTags(for: fountain.id)
            if !tags.isEmpty {
                FlowLayout(spacing: 7) {
                    ForEach(tags) { TagChip(label: $0.localizedLabel) }
                }
                .padding(.top, 14)
            }

            if reports.isEmpty {
                Text("Seja o primeiro a avaliar esta fonte: como está a água, e se vale a caminhada.")
                    .font(Typo.ui(14))
                    .foregroundStyle(Palette.ink.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(shown) { ReportRow(report: $0) }
                }
                .padding(.top, 8)

                if reports.count > Self.preview {
                    Button(showingAll
                        ? String(localized: "Ver menos")
                        : String(localized: "Ver todos os \(reports.count) relatos")
                    ) { showingAll.toggle() }
                    .font(Typo.ui(13.5, 600))
                    .foregroundStyle(Palette.green)
                    .padding(.top, 10)
                }
            }

            SecondaryButton(
                title: String(localized: "Avaliar esta fonte"), height: 46,
                tint: Palette.green, icon: Icon.Drop()
            ) { composing = true }
            .padding(.top, 16)

            footnote
                .padding(.top, 10)
        }
        .animation(Motion.ui, value: showingAll)
        .task { await community.refresh(fountainID: fountain.id) }
        .sheet(isPresented: $composing) {
            ReviewSheet(fountain: fountain)
        }
    }

    @ViewBuilder
    private func header(_ summary: CommunitySummary) -> some View {
        if let average = summary.average {
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(average.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "pt_BR"))))
                    .font(Typo.display(40))
                    .foregroundStyle(Palette.ink)
                VStack(alignment: .leading, spacing: 4) {
                    LozengeRating(value: average, size: 15)
                    Text(summary.ratingCount == 1
                        ? String(localized: "1 avaliação")
                        : String(localized: "\(summary.ratingCount) avaliações"))
                        .font(Typo.ui(12.5))
                        .foregroundStyle(Palette.ink.opacity(0.55))
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 6)
        } else {
            HStack(spacing: 10) {
                LozengeRating(value: 0, size: 15)
                Text("Sem avaliações")
                    .font(Typo.ui(12.5))
                    .foregroundStyle(Palette.ink.opacity(0.55))
            }
            .padding(.top, 6)
        }
    }

    /// Says where reports go and what is waiting, so nobody is surprised that
    /// theirs is public — or that it has not left the phone yet.
    private var footnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            if community.pendingCount > 0 {
                Text(community.pendingCount == 1
                    ? String(localized: "1 relato aguardando envio")
                    : String(localized: "\(community.pendingCount) relatos aguardando envio"))
                    .font(Typo.ui(12, 600))
                    .foregroundStyle(Palette.ink.opacity(0.7))
            }
            Text(CommunityNotice.text(for: community.availability, failed: community.lastRefreshFailed))
                .font(Typo.ui(11.5))
                .foregroundStyle(Palette.ink.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One-line explanations of where reports go, shared by every screen that has one.
enum CommunityNotice {
    static func text(for availability: CommunityAvailability, failed: Bool) -> String {
        switch availability {
        case .localOnly:
            String(localized: "Nesta versão os relatos ficam só neste aparelho.")
        case .signedOut:
            String(localized: "Entre no iCloud, nos Ajustes do iOS, para compartilhar. Até lá, os relatos ficam salvos aqui.")
        case .restricted:
            String(localized: "O iCloud está restrito neste aparelho. Os relatos ficam salvos aqui.")
        case .ready, .unavailable:
            failed
                ? String(localized: "Sem conexão: mostrando os últimos relatos baixados.")
                : String(localized: "Relatos são públicos e anônimos.")
        }
    }
}
