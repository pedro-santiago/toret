import SwiftUI
import UIKit

private extension String {
    /// "DISTÂNCIA" becomes "Distância". Captions used to be set in tracked
    /// capitals; the poster keeps its capitals for the display words, so the
    /// existing call sites are folded to sentence case here.
    var sentenceCased: String {
        guard !isEmpty else { return self }
        let lower = lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }
}

// MARK: - Search

/// The search field: a plate with a heavy frame, a magnifier, and a cross to clear it.
struct SearchPill: View {
    @Binding var text: String
    var placeholder = String(localized: "Buscar rua, praça ou bairro")

    var body: some View {
        HStack(spacing: 12) {
            IconView(shape: Icon.Magnifier(), size: 18, weight: 2.4, tint: Palette.inchiostro)

            TextField(text: $text) {
                Text(placeholder)
                    .font(Typo.ui(16))
                    .foregroundStyle(Palette.ink(0.62))
            }
            .font(Typo.ui(16, 500))
            .foregroundStyle(Palette.inchiostro)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Icon.Cross()
                        .stroke(Palette.inchiostro, style: StrokeStyle(lineWidth: 2.4))
                        .frame(width: 12, height: 12)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Limpar a busca"))
                .transition(.opacity)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, text.isEmpty ? 16 : 2)
        .frame(minHeight: 52)
        .glassCapsule(tone: .paper)
        .animation(ScreenMotion.snap, value: text.isEmpty)
    }
}

// MARK: - Filters

/// The chips under the search field: frames that fill with ink when they are on.
///
/// They scroll sideways rather than shrink, because four honest labels do not fit
/// in one row at any size worth reading. Each shows how many fountains it would
/// keep, so a chip that matches nothing says so before it is pressed.
struct FilterChips: View {
    let active: Set<MapFilter>
    let toggle: (MapFilter) -> Void

    @Environment(ToretModel.self) private var model: ToretModel?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MapFilter.allCases) { filter in
                    chip(filter)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: active)
        .animation(ScreenMotion.snap, value: active)
    }

    private func count(_ filter: MapFilter) -> Int? {
        // "Sem relato de seca" keeps nearly everything; a count there is noise.
        guard filter != .notDry, let model else { return nil }
        return model.fountains.count { filter.matches($0) }
    }

    private func chip(_ filter: MapFilter) -> some View {
        let isOn = active.contains(filter)
        let matches = count(filter)
        return Button { toggle(filter) } label: {
            HStack(spacing: 8) {
                Text(filter.title)
                    .font(Typo.ui(14, 700))
                if let matches {
                    Text("\(matches)")
                        .font(Typo.ui(13, 500))
                        .opacity(0.75)
                }
            }
            .foregroundStyle(isOn ? Palette.carta : Palette.inchiostro)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(isOn ? Palette.inchiostro : Palette.carta)
            .overlay { Rectangle().strokeBorder(Palette.inchiostro, lineWidth: 2) }
            // A 44 pt target around a 36 pt chip.
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.title)
        .accessibilityValue(matches.map { String(localized: "\($0) fontes") } ?? "")
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - The compass, in miniature

/// The black plate that keeps the needle on screen while you are looking at
/// something else. The sun is the dial; tapping the plate opens the compass.
struct CompassPill: View {
    let fountain: Fountain
    let needleAngle: Double
    let token: Int
    var isNearest: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Palette.sole)
                    Needle(
                        angle: needleAngle, diameter: 34,
                        headWidth: 10, headHeight: 13, headInset: 4,
                        tint: Palette.inchiostro
                    )
                    .animation(Motion.needle, value: token)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        distance
                        Text(fountain.place)
                            .font(Typo.ui(14, 700))
                            .foregroundStyle(Palette.carta)
                            .lineLimit(1)
                    }
                    Text(isNearest ? String(localized: "Fonte mais próxima") : String(localized: "Fonte selecionada"))
                        .font(Typo.ui(12, 500))
                        .foregroundStyle(Palette.carta.opacity(0.8))
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 16)
            .frame(minHeight: 56)
            .glassCapsule(tone: .ink)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(String(localized: "Bússola. \(fountain.place), \(Distance.spoken(fountain.distance))"))
        .accessibilityHint(String(localized: "Abre a bússola em tela cheia"))
    }

    @ViewBuilder private var distance: some View {
        if fountain.distance < 1000 {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                CountingMetres(
                    metres: fountain.distance, token: token,
                    size: 22, weight: 800, color: Palette.carta
                )
                Text("m").font(Typo.ui(13, 600)).foregroundStyle(Palette.carta.opacity(0.8))
            }
            .fixedSize()
        } else {
            Text(Distance.text(fountain.distance))
                .font(Typo.display(22, 800))
                .foregroundStyle(Palette.carta)
                .fixedSize()
        }
    }
}

// MARK: - Statistics

/// A figure and its caption — the unit of measurement everywhere in the app.
///
/// The figure is poster type; the caption is a plain sentence under it. Callers
/// still pass the old capitals ("DISTÂNCIA"); they are folded to sentence case.
struct StatBlock: View {
    let value: String
    let caption: String
    var valueColor: Color = Palette.inchiostro
    var size: CGFloat = 20
    var captionColor: Color = Palette.ink(0.72)
    /// Interface-face values (a water state) rather than poster figures.
    var isProse: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(isProse ? Typo.ui(15, 700) : Typo.display(size, 800))
                .foregroundStyle(valueColor)
                .fixedSize(horizontal: false, vertical: true)
            Text(caption.sentenceCased)
                .font(Typo.ui(13, 500))
                .foregroundStyle(captionColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The heavy vertical rule between two statistics.
struct StatDivider: View {
    var color: Color = Palette.inchiostro
    var height: CGFloat = 30

    var body: some View {
        Rectangle().fill(color).frame(width: 3, height: height)
            .accessibilityHidden(true)
    }
}

// MARK: - Specification rows

/// A label and its value on one line, with a light rule under it.
struct SpecRow: View {
    let label: String
    let value: String

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) { labelText; valueText }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    labelText
                    Spacer(minLength: 0)
                    valueText.multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { PosterRule(weight: .light) }
        .accessibilityElement(children: .combine)
    }

    private var labelText: some View {
        Text(label)
            .font(Typo.ui(15))
            .foregroundStyle(Palette.ink(0.72))
    }

    private var valueText: some View {
        Text(value)
            .font(Typo.ui(15, 700))
            .foregroundStyle(Palette.inchiostro)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Buttons

/// The black bar that commits you to walking somewhere, with the sun at its end.
///
/// Attention actions pass `background: Palette.rosso`. Pressed, it slips two
/// points down and to the right, like a plate printed slightly out of register.
struct PrimaryButton: View {
    let title: String
    var height: CGFloat = 56
    var fontSize: CGFloat = 20
    var background: Color = Palette.inchiostro
    var foreground: Color = Palette.carta
    var leadingDot: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let leadingDot {
                    Circle().fill(leadingDot).frame(width: 10, height: 10)
                }
                Text(title)
                    .textCase(.uppercase)
                    .font(Typo.display(max(fontSize, 17), 800))
                    .foregroundStyle(foreground)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Circle().fill(Palette.sole).frame(width: 26, height: 26)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: height)
            .background(background)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
    }
}

/// The framed bar for the action you could take but need not.
struct SecondaryButton<Glyph: Shape>: View {
    let title: String
    var height: CGFloat = 52
    var tint: Color = Palette.inchiostro
    var icon: Glyph?
    let action: () -> Void

    init(
        title: String, height: CGFloat = 52, tint: Color = Palette.inchiostro,
        icon: Glyph? = nil, action: @escaping () -> Void
    ) {
        self.title = title
        self.height = height
        self.tint = tint
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    IconView(shape: icon, size: 16, weight: 2.2, tint: tint)
                }
                Text(title)
                    .textCase(.uppercase)
                    .font(Typo.display(16, 800))
                    .foregroundStyle(tint)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: height)
            .overlay { Rectangle().strokeBorder(tint, lineWidth: 2.5) }
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
    }
}

extension SecondaryButton where Glyph == Icon.Cross {
    /// A framed button with no glyph.
    init(title: String, height: CGFloat = 52, tint: Color = Palette.inchiostro, action: @escaping () -> Void) {
        self.init(title: title, height: height, tint: tint, icon: nil, action: action)
    }
}

/// A round icon button — save, share, close. A circle is the one curve the poster allows.
struct GlyphButton<Glyph: View>: View {
    var diameter: CGFloat = 50
    var tone: GlassTone = .paper
    var accessibilityText: String
    @ViewBuilder let glyph: () -> Glyph
    let action: () -> Void

    var body: some View {
        // A target of at least 44 pt without changing the layout: the extra is
        // padded in and taken out again.
        let extra = max(0, (44 - diameter) / 2)
        Button(action: action) {
            glyph()
                .frame(width: diameter, height: diameter)
                .glassPane(Circle(), tone: tone, interactive: true)
                .padding(extra)
                .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .padding(-extra)
        .accessibilityLabel(accessibilityText)
    }
}

/// Buttons in this app are pressed, not lit: the label slips two points down and
/// to the right and comes back when you let go. Under Reduce Motion it still
/// slips, it just does not travel there.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? 2 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// A square switch: a framed track with a square stop. Off, the stop is black and
/// sits left; on, the track fills black and the stop turns yellow and slides right.
struct PosterToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let isOn = configuration.isOn
        return Button { configuration.isOn.toggle() } label: {
            HStack(alignment: .center, spacing: 16) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Rectangle().fill(isOn ? Palette.inchiostro : Palette.carta)
                    Rectangle().strokeBorder(Palette.inchiostro, lineWidth: 2.5)
                    Rectangle()
                        .fill(isOn ? Palette.sole : Palette.inchiostro)
                        .frame(width: 22, height: 22)
                        .offset(x: isOn ? 14 : -14)
                }
                .frame(width: 58, height: 34)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .animation(ScreenMotion.snap, value: isOn)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isOn ? String(localized: "Ligado") : String(localized: "Desligado"))
        .accessibilityAddTraits(.isToggle)
    }
}

// MARK: - Legend

/// What the four shapes mean, in one line. Colour is never the only channel, but a
/// shape still has to be learned once; this is where it is taught.
struct StateLegend: View {
    var night = false

    private let states: [WaterState] = [.running, .weak, .dry, .unknown]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { items }
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading),
                ],
                alignment: .leading, spacing: 8
            ) { items }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Legenda das marcas: círculo, água corrente; meio disco, fluxo fraco; triângulo, sem água; anel vazio, sem relato recente"))
    }

    @ViewBuilder private var items: some View {
        ForEach(states, id: \.self) { state in
            HStack(spacing: 6) {
                StateMark(state: state, size: 14, night: night)
                Text(state.shortLabel)
                    .font(Typo.ui(13, 500))
                    .foregroundStyle(night ? Palette.carta.opacity(0.85) : Palette.ink(0.8))
                    .fixedSize()
            }
        }
    }
}

// MARK: - Location banner

/// Says, in one plate, why the distances on screen are what they are.
///
/// Shown whenever they are *not* measured from the user. A quiet fallback to the
/// old town would put a plausible, wrong number on the one thing the app exists
/// to tell you. The mark is a diamond — never a water-state shape — and the frame
/// is red when something is wrong and black when it is only worth knowing.
struct LocationBanner: View {
    let status: LocationStatus

    @Environment(\.openURL) private var openURL

    /// What to say, whether the fix is the user's to repair, and how loud to be.
    struct Message: Equatable {
        enum Tone { case warning, note }
        let text: String
        let opensSettings: Bool
        let settingsTitle: String
        let tone: Tone
    }

    /// Nil when there is nothing to say: the answer to "where am I measured from?"
    /// is "you", or the system is about to ask.
    static func message(for status: LocationStatus) -> Message? {
        let anchor = String(localized: "Piazza San Carlo")
        switch status {
        case .asking, .live:
            return nil
        case .searching:
            return Message(
                text: String(localized: "Procurando a sua posição."),
                opensSettings: false, settingsTitle: "", tone: .note
            )
        case .denied:
            return Message(
                text: String(localized: "A localização está desligada. As distâncias são medidas a partir da \(anchor)."),
                opensSettings: true, settingsTitle: String(localized: "Abrir Ajustes"), tone: .warning
            )
        case .restricted:
            return Message(
                text: String(localized: "A localização está bloqueada neste aparelho. As distâncias são medidas a partir da \(anchor)."),
                opensSettings: false, settingsTitle: "", tone: .warning
            )
        case .approximate:
            return Message(
                text: String(localized: "A localização é aproximada, então as distâncias podem errar por centenas de metros."),
                opensSettings: true, settingsTitle: String(localized: "Ativar posição precisa"), tone: .note
            )
        case let .outsideTurin(kilometres):
            let far = kilometres.formatted(.number)
            return Message(
                text: String(localized: "Você está a \(far) km de Turim. As distâncias são medidas a partir da \(anchor)."),
                opensSettings: false, settingsTitle: "", tone: .note
            )
        }
    }

    var body: some View {
        if let message = Self.message(for: status) {
            let frame = message.tone == .warning ? Palette.rosso : Palette.inchiostro
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    if let scene = EmptySceneKind(location: status) {
                        // The drawn scene stands in for the plain mark: the compass struck
                        // through, or the dashed line to a far-off Turin.
                        EmptySceneMini(kind: scene.art, height: 56, distanceLabel: nil)
                    } else {
                        Diamond()
                            .fill(message.tone == .warning ? Palette.rosso : Palette.sole)
                            .overlay { Diamond().stroke(Palette.inchiostro, lineWidth: 2) }
                            .frame(width: 20, height: 20)
                            .padding(.top, 1)
                    }
                    Text(message.text)
                        .font(Typo.ui(14, 500))
                        .foregroundStyle(Palette.inchiostro)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if message.opensSettings {
                    SecondaryButton(title: message.settingsTitle, height: 44) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .plate(fill: Palette.cartaChiara, border: frame, lineWidth: 2.5)
            .transition(.opacity.combined(with: .offset(y: -8)))
            .accessibilityElement(children: .contain)
        }
    }
}

// MARK: - Search results

/// What the search field found, as a plate under it. Tapping one flies the map
/// there, clears the field and puts the keyboard away.
struct SearchResults: View {
    @Environment(ToretModel.self) private var model

    var body: some View {
        let results = model.searchResults
        VStack(spacing: 0) {
            if results.isEmpty {
                EmptyScene(kind: .noResults, layout: .row)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
            } else {
                ForEach(results) { fountain in
                    FountainRow(fountain: fountain, compact: true) {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                        )
                        model.select(fountain)
                        model.searchText = ""
                    }
                    .padding(.horizontal, 14)
                }
            }
        }
        .glassPane(cornerRadius: 0, tone: .paper)
        .animation(ScreenMotion.morph, value: results.map(\.id))
    }
}
