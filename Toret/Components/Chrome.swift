import SwiftUI

// MARK: - Search

/// The search field, as a pane of glass floating over the map.
struct SearchPill: View {
    @Binding var text: String
    var placeholder = "Buscar fonte, praça ou endereço"

    var body: some View {
        HStack(spacing: 10) {
            IconView(
                shape: Icon.Magnifier(), size: 15, weight: 1.9,
                tint: Palette.ink.opacity(0.45)
            )

            TextField(text: $text) {
                Text(placeholder)
                    .font(Typo.ui(15))
                    .foregroundStyle(Palette.ink.opacity(0.5))
            }
            .font(Typo.ui(15))
            .foregroundStyle(Palette.ink)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .glassCapsule(tone: .paper)
    }
}

// MARK: - Filters

/// The chips under the search field.
struct FilterChips: View {
    let active: Set<MapFilter>
    let toggle: (MapFilter) -> Void

    var body: some View {
        HStack(spacing: 7) {
            ForEach(MapFilter.allCases) { filter in
                let isOn = active.contains(filter)
                Button { toggle(filter) } label: {
                    HStack(spacing: 6) {
                        if isOn {
                            Circle()
                                .fill(Palette.paperRaised)
                                .frame(width: 7, height: 7)
                        }
                        Text(filter.rawValue)
                            .font(Typo.ui(12.5, 500))
                            .foregroundStyle(isOn ? Palette.paperRaised : Palette.ink)
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 32)
                    .background {
                        if isOn {
                            Capsule()
                                .fill(Palette.green)
                                .shadow(color: Palette.ink.opacity(0.16), radius: 6, y: 4)
                        }
                    }
                    .glassCapsule(tone: .paper, interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
            }
            Spacer(minLength: 0)
        }
        .animation(Motion.ui, value: active)
    }
}

// MARK: - The compass, in miniature

/// The pill that keeps the needle on screen while you are looking at something
/// else. Tapping it opens the compass full screen.
struct CompassPill: View {
    let fountain: Fountain
    let needleAngle: Double
    let token: Int
    var isNearest: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                ZStack {
                    Circle().strokeBorder(Palette.sage.opacity(0.45), lineWidth: 1.5)
                    Needle.pill(angle: needleAngle)
                        .animation(Motion.needle, value: token)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        CountingMetres(
                            metres: fountain.distance, token: token,
                            size: 13, weight: 600, color: Palette.paperRaised
                        )
                        Text("m · \(fountain.place)")
                            .font(Typo.ui(12.5, 600))
                            .foregroundStyle(Palette.paperRaised)
                    }
                    Text(isNearest ? "FONTE MAIS PRÓXIMA" : "FONTE SELECIONADA")
                        .font(Typo.narrow(8.5))
                        .tracking(Typo.tracking(0.14, at: 8.5))
                        .foregroundStyle(Palette.paperRaised.opacity(0.5))
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 16)
            .frame(height: 46)
            .glassCapsule(tone: .ink)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Bússola. \(fountain.place), \(fountain.distance) metros")
        .accessibilityHint("Abre a bússola em tela cheia")
    }
}

// MARK: - Statistics

/// A figure and its caption — the unit of measurement everywhere in the app.
struct StatBlock: View {
    let value: String
    let caption: String
    var valueColor: Color = Palette.ink
    var size: CGFloat = 20
    var captionColor: Color = Palette.ink.opacity(0.5)
    /// Interface-face values (a water state) rather than poster figures.
    var isProse: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(isProse ? Typo.ui(14, 500) : Typo.display(size))
                .foregroundStyle(valueColor)
                .fixedSize(horizontal: false, vertical: true)
            Text(caption)
                .font(Typo.narrow(8.5))
                .tracking(Typo.tracking(0.12, at: 8.5))
                .foregroundStyle(captionColor)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The hairline between two statistics.
struct StatDivider: View {
    var color: Color = Palette.ink.opacity(0.12)
    var height: CGFloat = 30

    var body: some View {
        Rectangle().fill(color).frame(width: 1, height: height)
    }
}

// MARK: - Specification rows

/// A label and its value on one line, with a hairline under it.
///
/// The whole lower half of the fountain page is built from these: the water, the
/// iron, the settings. Right-aligned values give the column of facts an edge to
/// be read down.
struct SpecRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(Typo.ui(14))
                .foregroundStyle(Palette.ink.opacity(0.62))
            Spacer(minLength: 0)
            Text(value)
                .font(Typo.ui(14, 500))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.ink.opacity(0.08)).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Buttons

/// The green pill that commits you to walking somewhere.
struct PrimaryButton: View {
    let title: String
    var height: CGFloat = 54
    var fontSize: CGFloat = 16
    var background: Color = Palette.green
    var foreground: Color = Palette.paperRaised
    var leadingDot: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let leadingDot {
                    Circle().fill(leadingDot).frame(width: 9, height: 9)
                }
                Text(title)
                    .font(Typo.ui(fontSize, 600))
                    .foregroundStyle(foreground)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Capsule().fill(background))
        }
        .buttonStyle(.pressable)
    }
}

/// The outlined pill for the action you should be able to take but rarely do.
struct SecondaryButton<Glyph: Shape>: View {
    let title: String
    var height: CGFloat = 48
    var tint: Color = Palette.terracotta
    var icon: Glyph?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    IconView(shape: icon, size: 14, weight: 1.6, tint: tint)
                }
                Text(title)
                    .font(Typo.ui(14.5, 500))
                    .foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 1.5))
        }
        .buttonStyle(.pressable)
    }
}

/// A round icon button — save, share, close.
struct GlyphButton<Glyph: View>: View {
    var diameter: CGFloat = 50
    var tone: GlassTone = .paper
    var accessibilityText: String
    @ViewBuilder let glyph: () -> Glyph
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            glyph()
                .frame(width: diameter, height: diameter)
                .glassPane(Circle(), tone: tone, interactive: true)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(accessibilityText)
    }
}

/// Buttons in this app dip rather than fade — the glass has to feel solid.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

// MARK: - Location banner

/// Says, in one line, why the distances on screen are what they are.
///
/// Shown whenever they are *not* measured from the user. The alternative — a
/// quiet fallback to the old town — would put a plausible, wrong number on the
/// one thing the app exists to tell you.
struct LocationBanner: View {
    let status: LocationStatus
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let message {
            HStack(spacing: 10) {
                IconView(shape: Icon.Rings(), size: 15, weight: 1.7, tint: Palette.ocre)
                Text(message)
                    .font(Typo.ui(12.5, 500))
                    .foregroundStyle(Palette.ink.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if needsSettings {
                    Button("Ajustes") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .font(Typo.ui(12.5, 600))
                    .foregroundStyle(Palette.green)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassPane(cornerRadius: 18, tone: .paper)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }

    private var needsSettings: Bool {
        switch status {
        case .denied, .approximate: true
        default: false
        }
    }

    private var message: String? {
        switch status {
        case .asking, .live: nil
        case .searching: "Procurando a sua posição…"
        case .denied: "Localização desligada. Distâncias medidas a partir da Piazza San Carlo."
        case .restricted: "Localização bloqueada neste aparelho. Distâncias medidas a partir da Piazza San Carlo."
        case .approximate: "Localização aproximada. Ative a posição precisa para distâncias exatas."
        case let .outsideTurin(kilometres):
            "Você está a \(kilometres.formatted(.number.locale(Locale(identifier: "pt_BR")))) km de Turim. Distâncias medidas a partir da Piazza San Carlo."
        }
    }
}

// MARK: - Search results

/// What the search field found, as a pane under it. Tapping one flies the map
/// there and clears the field.
struct SearchResults: View {
    @Environment(ToretModel.self) private var model

    var body: some View {
        let results = model.searchResults
        VStack(spacing: 0) {
            if results.isEmpty {
                Text("Nenhuma fonte encontrada")
                    .font(Typo.ui(14))
                    .foregroundStyle(Palette.ink.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                ForEach(results) { fountain in
                    Button {
                        model.select(fountain)
                        model.searchText = ""
                    } label: {
                        HStack(spacing: 12) {
                            Needle.row(
                                angle: fountain.bearing, tint: fountain.state.color,
                                stem: Palette.ink.opacity(0.2), diameter: 20
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fountain.place)
                                    .font(Typo.ui(14.5, 500))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                Text("\(fountain.plateTitle) · \(fountain.zone)")
                                    .font(Typo.ui(12))
                                    .foregroundStyle(Palette.ink.opacity(0.5))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Text("\(fountain.distance) m")
                                .font(Typo.display(16))
                                .foregroundStyle(Palette.ink.opacity(0.75))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .glassPane(cornerRadius: 22, tone: .paper)
    }
}
