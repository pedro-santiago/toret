import SwiftUI

/// Rating a fountain: what the water is doing, how good it is, and a line about it.
///
/// Everything is optional except having *something* to say. Submitting returns
/// at once — the report is queued and the sheet says where it will go — so this
/// works in a tunnel, with no iCloud, and with a build that shares nothing.
struct ReviewSheet: View {
    let fountain: Fountain

    @Environment(Community.self) private var community
    @Environment(\.dismiss) private var dismiss

    @State private var water: WaterState?
    @State private var rating = 0
    @State private var tags: [ReportTag] = []
    @State private var note = ""
    @State private var sent: SubmitDelivery?
    @State private var rejection: SubmitRejection?
    @State private var tagOverflow = 0
    @FocusState private var noteFocused: Bool

    private var canSubmit: Bool { water != nil || rating > 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let sent {
                    confirmation(sent)
                } else {
                    PosterTitle("AVA", "LIAR", size: 64)
                    Text(fountain.place)
                        .font(Typo.ui(18, 700))
                        .foregroundStyle(Palette.inchiostro)
                        .padding(.top, 14)
                    form
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 32)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.carta)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: sent)
        .sensoryFeedback(.error, trigger: rejection)
        .sensoryFeedback(.warning, trigger: tagOverflow)
    }

    // MARK: Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            group(String(localized: "Como está a água")) {
                HStack(spacing: 8) {
                    ForEach(WaterState.reportable, id: \.self) { waterTile($0) }
                }
            }

            group(String(localized: "Sua nota")) {
                DiamondRatingInput(rating: $rating)
            }

            group(String(localized: "O que você notou, até 3")) {
                FlowLayout(spacing: 8) {
                    ForEach(ReportTag.allCases) { tag in
                        Button { toggle(tag) } label: {
                            TagChip(label: tag.localizedLabel, isOn: tags.contains(tag))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(tags.contains(tag) ? .isSelected : [])
                    }
                }
            }

            group(String(localized: "Uma linha, se quiser")) {
                VStack(alignment: .trailing, spacing: 6) {
                    TextField(
                        String(localized: "Água gelada, fila pequena"),
                        text: $note, axis: .vertical
                    )
                    .lineLimit(2 ... 4)
                    .font(Typo.ui(16))
                    .foregroundStyle(Palette.inchiostro)
                    .focused($noteFocused)
                    .padding(14)
                    .background(Palette.cartaChiara)
                    .overlay { Rectangle().strokeBorder(Palette.inchiostro, lineWidth: 2) }
                    .onChange(of: note) {
                        if note.count > Report.maximumNoteLength {
                            note = String(note.prefix(Report.maximumNoteLength))
                        }
                        rejection = nil
                    }

                    Text("\(note.count)/\(Report.maximumNoteLength)")
                        .font(Typo.ui(13))
                        .foregroundStyle(Palette.inchiostro.opacity(0.7))
                        .monospacedDigit()
                }
            }

            if let rejection {
                Text(message(for: rejection))
                    .font(Typo.ui(15, 600))
                    .foregroundStyle(Palette.rosso)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }

            PrimaryButton(title: String(localized: "Enviar relato"), height: 56) { submit() }
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.4)
                .padding(.top, 24)

            Text(CommunityNotice.text(for: community.availability, failed: false))
                .font(Typo.ui(13))
                .foregroundStyle(Palette.inchiostro.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
    }

    /// A heavy rule, a plain heading, and the control: the poster's own grouping.
    private func group<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PosterRule()
            Text(title)
                .font(Typo.ui(16, 700))
                .foregroundStyle(Palette.inchiostro)
            content()
        }
        .padding(.top, 26)
    }

    private func waterTile(_ state: WaterState) -> some View {
        let isOn = water == state
        return Button {
            water = isOn ? nil : state
            rejection = nil
        } label: {
            VStack(spacing: 10) {
                StateMark(state: state, size: 30, night: isOn)
                Text(state.shortLabel)
                    .font(Typo.ui(14, 700))
                    .foregroundStyle(isOn ? Palette.carta : Palette.inchiostro)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .background(isOn ? Palette.inchiostro : Palette.cartaChiara)
            .overlay { Rectangle().strokeBorder(Palette.inchiostro, lineWidth: isOn ? 3 : 2) }
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.selection, trigger: water)
        .accessibilityLabel(state.label)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: Sending

    private func toggle(_ tag: ReportTag) {
        if let index = tags.firstIndex(of: tag) {
            tags.remove(at: index)
        } else if tags.count < 3 {
            tags.append(tag)
        } else {
            tagOverflow += 1
        }
    }

    private func submit() {
        noteFocused = false
        let result = community.submit(ReportDraft(
            fountainID: fountain.id, state: water, rating: rating, tags: tags, note: note
        ))
        switch result {
        case let .accepted(delivery):
            rejection = nil
            withAnimation(Motion.ui) { sent = delivery }
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                dismiss()
            }
        case let .rejected(reason):
            rejection = reason
        }
    }

    private func message(for rejection: SubmitRejection) -> String {
        switch rejection {
        case .empty:
            String(localized: "Escolha como está a água ou dê uma nota.")
        case .objectionable:
            String(localized: "Tire as palavras ofensivas para enviar.")
        case .containsContact:
            String(localized: "Links, e-mails e telefones não são aceitos nos relatos.")
        case let .rateLimited(minutes):
            String(localized: "Você já avaliou esta fonte agora há pouco. Tente de novo em \(minutes) min.")
        }
    }

    // MARK: Confirmation

    private func confirmation(_ delivery: SubmitDelivery) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            StateMark(state: water ?? .unknown, size: 56)
            PosterTitle("OBRI", "GADO", size: 64)
            Text(deliveryText(delivery))
                .font(Typo.ui(16))
                .foregroundStyle(Palette.inchiostro)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 24)
        .accessibilityElement(children: .combine)
        .transition(.opacity)
    }

    private func deliveryText(_ delivery: SubmitDelivery) -> String {
        switch delivery {
        case .sending:
            String(localized: "O relato já aparece para quem estiver por perto.")
        case .waitingForICloud:
            String(localized: "Salvo. Entre no iCloud para compartilhar; o envio é automático.")
        case .waitingForConnection:
            String(localized: "Salvo, será enviado quando houver conexão.")
        case .deviceOnly:
            String(localized: "Salvo neste aparelho.")
        }
    }
}
