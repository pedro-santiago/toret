import SwiftUI

/// One report: what the water was doing, the rating, the note, who and when —
/// and the menu that makes the feature safe to open to strangers.
///
/// Used under a fountain's rating (where the fountain is obvious) and in the
/// city feed (where it is not, and `fountain` names it).
struct ReportRow: View {
    let report: Report
    /// Set in the city feed, where each row has to say which fountain it is about.
    var fountain: Fountain?
    var onOpenFountain: (() -> Void)?

    @Environment(Community.self) private var community
    @State private var choosingReason = false
    @State private var confirmingBlock = false
    @State private var confirmingDelete = false

    private var isMine: Bool { community.isMine(report) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StateGlyph(state: report.state, size: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                if let fountain {
                    Button { onOpenFountain?() } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(fountain.place)
                                .font(Typo.ui(15, 600))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(fountain.distance) m")
                                .font(Typo.display(15))
                                .foregroundStyle(Palette.ink.opacity(0.7))
                        }
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    Text(report.state == .unknown ? String(localized: "Só avaliação") : report.state.label)
                        .font(Typo.ui(13, 600))
                        .foregroundStyle(report.state.color)
                    if let rating = report.rating {
                        LozengeRating(value: Double(rating), size: 11, spacing: 3)
                    }
                }

                if !report.tags.isEmpty {
                    Text(report.tags.map(\.localizedLabel).joined(separator: " · "))
                        .font(Typo.ui(12.5))
                        .foregroundStyle(Palette.ink.opacity(0.6))
                }

                if !report.note.isEmpty {
                    Text(report.note)
                        .font(Typo.ui(14))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Text(isMine ? String(localized: "Você") : report.author)
                    Text("·")
                    Text(report.ago)
                    if community.isPending(report) {
                        Text("·")
                        Text(String(localized: "aguardando envio"))
                    }
                }
                .font(Typo.ui(12))
                .foregroundStyle(Palette.ink.opacity(0.5))
            }

            Spacer(minLength: 0)

            menu
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.ink.opacity(0.08)).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .confirmationDialog(
            String(localized: "Por que denunciar este relato?"),
            isPresented: $choosingReason, titleVisibility: .visible
        ) {
            Button(String(localized: "Ofensivo ou abusivo")) { community.flag(report, reason: "offensive") }
            Button(String(localized: "Spam ou propaganda")) { community.flag(report, reason: "spam") }
            Button(String(localized: "Informação falsa")) { community.flag(report, reason: "false") }
            Button(String(localized: "Cancelar"), role: .cancel) {}
        } message: {
            Text("O relato some para você agora e é enviado para revisão.")
        }
        .confirmationDialog(
            String(localized: "Bloquear \(report.author)?"),
            isPresented: $confirmingBlock, titleVisibility: .visible
        ) {
            Button(String(localized: "Bloquear"), role: .destructive) { community.block(author: report.author) }
            Button(String(localized: "Cancelar"), role: .cancel) {}
        } message: {
            Text("Você deixa de ver tudo o que esta pessoa escreve. É possível desfazer na aba Relatos.")
        }
        .confirmationDialog(
            String(localized: "Apagar o seu relato?"),
            isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button(String(localized: "Apagar"), role: .destructive) { community.deleteMine(report) }
            Button(String(localized: "Cancelar"), role: .cancel) {}
        }
    }

    private var menu: some View {
        Menu {
            if isMine {
                Button(String(localized: "Apagar meu relato"), systemImage: "trash", role: .destructive) {
                    confirmingDelete = true
                }
            } else {
                Button(String(localized: "Denunciar"), systemImage: "flag") { choosingReason = true }
                Button(String(localized: "Bloquear autor"), systemImage: "hand.raised", role: .destructive) {
                    confirmingBlock = true
                }
            }
        } label: {
            HStack(spacing: 3) {
                ForEach(0 ..< 3, id: \.self) { _ in
                    Circle().fill(Palette.ink.opacity(0.45)).frame(width: 3.5, height: 3.5)
                }
            }
            .frame(width: 34, height: 34)
            .contentShape(.rect)
        }
        .accessibilityLabel(String(localized: "Mais opções"))
    }
}
