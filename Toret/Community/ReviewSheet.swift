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
                Eyebrow(text: String(localized: "Avaliar"))
                DisplayText(fountain.titleLines, size: 30, leading: 1.05)
                    .padding(.top, 6)

                if let sent {
                    confirmation(sent)
                } else {
                    form
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 28)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.paper)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: sent)
        .sensoryFeedback(.error, trigger: rejection)
        .sensoryFeedback(.warning, trigger: tagOverflow)
    }

    // MARK: Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            label(String(localized: "A água agora"))
            HStack(spacing: 8) {
                ForEach(WaterState.reportable, id: \.self) { state in
                    waterTile(state)
                }
            }

            label(String(localized: "Sua nota"))
            LozengeRatingInput(rating: $rating)

            label(String(localized: "O que você notou (até 3)"))
            FlowLayout(spacing: 8) {
                ForEach(ReportTag.allCases) { tag in
                    Button { toggle(tag) } label: {
                        TagChip(label: tag.localizedLabel, isOn: tags.contains(tag))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tags.contains(tag) ? .isSelected : [])
                }
            }

            label(String(localized: "Uma linha, se quiser"))
            VStack(alignment: .trailing, spacing: 6) {
                TextField(
                    String(localized: "Ex.: água gelada, fila pequena"),
                    text: $note, axis: .vertical
                )
                .lineLimit(2 ... 4)
                .font(Typo.ui(15))
                .foregroundStyle(Palette.ink)
                .focused($noteFocused)
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Palette.ink.opacity(0.25), lineWidth: 1.2)
                }
                .onChange(of: note) {
                    if note.count > Report.maximumNoteLength {
                        note = String(note.prefix(Report.maximumNoteLength))
                    }
                    rejection = nil
                }

                Text("\(note.count)/\(Report.maximumNoteLength)")
                    .font(Typo.ui(11.5))
                    .foregroundStyle(Palette.ink.opacity(0.45))
                    .monospacedDigit()
            }

            if let rejection {
                Text(message(for: rejection))
                    .font(Typo.ui(13, 500))
                    .foregroundStyle(Palette.terracotta)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }

            PrimaryButton(title: String(localized: "Enviar relato"), height: 52) { submit() }
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.4)
                .padding(.top, 22)

            Text(CommunityNotice.text(for: community.availability, failed: false))
                .font(Typo.ui(11.5))
                .foregroundStyle(Palette.ink.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }

    private func waterTile(_ state: WaterState) -> some View {
        let isOn = water == state
        return Button {
            water = isOn ? nil : state
            rejection = nil
        } label: {
            VStack(spacing: 8) {
                StateGlyph(state: state, size: 24)
                Text(state.shortLabel)
                    .font(Typo.ui(13, 600))
                    .foregroundStyle(Palette.ink)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isOn ? state.color.opacity(0.14) : Color.clear)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isOn ? state.color : Palette.ink.opacity(0.25), lineWidth: isOn ? 2 : 1.2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.selection, trigger: water)
        .accessibilityLabel(state.label)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Typo.narrow(9.5))
            .tracking(Typo.tracking(0.14, at: 9.5))
            .foregroundStyle(Palette.ink.opacity(0.5))
            .padding(.top, 24)
            .padding(.bottom, 10)
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
            sent = delivery
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
        VStack(alignment: .leading, spacing: 12) {
            StateGlyph(state: water ?? .unknown, size: 34)
                .padding(.top, 36)
            Text("Obrigado")
                .font(Typo.display(34))
                .foregroundStyle(Palette.ink)
            Text(deliveryText(delivery))
                .font(Typo.ui(15))
                .foregroundStyle(Palette.ink.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
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
