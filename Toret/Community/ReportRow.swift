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
        HStack(alignment: .top, spacing: 14) {
            StateMark(state: report.state, size: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                if let fountain {
                    Button { onOpenFountain?() } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(fountain.place)
                                .font(Typo.ui(18, 700))
                                .foregroundStyle(Palette.inchiostro)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(fountain.distance)")
                                    .font(Typo.display(26))
                                Text("m").font(Typo.ui(14))
                            }
                            .foregroundStyle(Palette.inchiostro)
                        }
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    Text(statement)
                        .font(Typo.ui(15, 600))
                        .foregroundStyle(Palette.inchiostro)
                    if let rating = report.rating {
                        DiamondRating(value: Double(rating), size: 12, spacing: 3)
                    }
                }

                if !report.tags.isEmpty {
                    Text(report.tags.map { $0.localizedLabel.lowercased() }.joined(separator: ", "))
                        .font(Typo.ui(14))
                        .foregroundStyle(Palette.inchiostro.opacity(0.7))
                }

                if !report.note.isEmpty {
                    Text(report.note)
                        .font(Typo.ui(16))
                        .foregroundStyle(Palette.inchiostro)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(byline)
                    .font(Typo.ui(13))
                    .foregroundStyle(Palette.inchiostro.opacity(0.7))
            }

            Spacer(minLength: 0)

            menu
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { PosterRule(weight: .light) }
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

    /// "Água corrente" — or, for a rating that said nothing about the water,
    /// "Só avaliação", so a row is never mistaken for a report of the unknown.
    private var statement: String {
        report.state == .unknown ? String(localized: "Só avaliação") : report.state.label
    }

    /// Who and when, in a sentence: "Você, há 2 h" or "Visitante 4F2A91, há 2 h".
    private var byline: String {
        var line = "\(isMine ? String(localized: "Você") : report.author), \(report.ago)"
        if community.isPending(report) { line += ". " + String(localized: "Aguardando envio") }
        return line
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
            HStack(spacing: 4) {
                ForEach(0 ..< 3, id: \.self) { _ in
                    Circle().fill(Palette.inchiostro).frame(width: 4.5, height: 4.5)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(.rect)
        }
        .accessibilityLabel(String(localized: "Mais opções"))
    }
}
