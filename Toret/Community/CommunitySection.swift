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
    @State private var composing: Bool
    @State private var showingAll = false

    private static let preview = 3

    init(fountain: Fountain) {
        self.fountain = fountain
        #if DEBUG
        // `-toret-compose` opens the review sheet, which the simulator cannot tap.
        _composing = State(initialValue: ProcessInfo.processInfo.arguments.contains("-toret-compose"))
        #else
        _composing = State(initialValue: false)
        #endif
    }

    var body: some View {
        let reports = community.reports(for: fountain.id)
        let summary = community.summary(for: fountain.id)
        let shown = showingAll ? reports : Array(reports.prefix(Self.preview))

        VStack(alignment: .leading, spacing: 0) {
            header(summary)

            let tags = community.topTags(for: fountain.id)
            if !tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(tags) { TagChip(label: $0.localizedLabel) }
                }
                .padding(.top, 16)
            }

            if reports.isEmpty {
                Text("Seja o primeiro a avaliar esta fonte: como está a água, e se vale a caminhada.")
                    .font(Typo.ui(16))
                    .foregroundStyle(Palette.inchiostro)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
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
                    .font(Typo.ui(15, 700))
                    .foregroundStyle(Palette.blu)
                    .padding(.top, 12)
                }
            }

            SecondaryButton(
                title: String(localized: "Avaliar esta fonte"), height: 52,
                tint: Palette.inchiostro, icon: Diamond()
            ) { composing = true }
            .padding(.top, 18)

            footnote
                .padding(.top, 12)
        }
        .background { debugAnchor }
        .animation(Motion.ui, value: showingAll)
        .task { await community.refresh(fountainID: fountain.id) }
        .sheet(isPresented: $composing) {
            ReviewSheet(fountain: fountain)
        }
    }

    /// Only in Debug builds: lets a screenshot script bring the section on screen.
    @ViewBuilder
    private var debugAnchor: some View {
        #if DEBUG
        DebugScrollIntoView()
        #else
        EmptyView()
        #endif
    }

    @ViewBuilder
    private func header(_ summary: CommunitySummary) -> some View {
        if let average = summary.average {
            HStack(alignment: .center, spacing: 16) {
                Text(Formatting.rating(average))
                    .font(Typo.display(56))
                    .foregroundStyle(Palette.inchiostro)
                VStack(alignment: .leading, spacing: 6) {
                    DiamondRating(value: average, size: 18)
                    Text(summary.ratingCount == 1
                        ? String(localized: "1 avaliação")
                        : String(localized: "\(summary.ratingCount) avaliações"))
                        .font(Typo.ui(14))
                        .foregroundStyle(Palette.inchiostro.opacity(0.7))
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
        } else {
            HStack(spacing: 12) {
                DiamondRating(value: 0, size: 18)
                Text("Sem avaliações")
                    .font(Typo.ui(14))
                    .foregroundStyle(Palette.inchiostro.opacity(0.7))
            }
            .padding(.top, 8)
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
                    .font(Typo.ui(13, 700))
                    .foregroundStyle(Palette.inchiostro)
            }
            Text(CommunityNotice.text(for: community.availability, failed: community.lastRefreshFailed))
                .font(Typo.ui(13))
                .foregroundStyle(Palette.inchiostro.opacity(0.7))
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

#if DEBUG
/// Scrolls the enclosing scroll view until this view is near the top, when the
/// app was launched with `-toret-focus-community`. The section sits halfway down
/// the detail page and the simulator cannot swipe, so this is the only way a
/// script can photograph it.
private struct DebugScrollIntoView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { UIView() }

    func updateUIView(_ view: UIView, context: Context) {
        guard ProcessInfo.processInfo.arguments.contains("-toret-focus-community") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            var parent = view.superview
            while let current = parent, !(current is UIScrollView) { parent = current.superview }
            guard let scroll = parent as? UIScrollView else { return }
            let frame = view.convert(view.bounds, to: scroll)
            scroll.setContentOffset(CGPoint(x: 0, y: max(0, frame.minY - 150)), animated: false)
        }
    }
}
#endif
