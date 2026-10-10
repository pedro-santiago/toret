import SwiftUI

/// One fountain, as a plate of the poster.
///
/// The top of the page is the picture: a toret under the sun, in front of the
/// arcades, drawn in the state the community last reported — running water only
/// if someone said so. Under it, the name in the poster's own type, one honest
/// sentence about the water, and the three numbers that decide whether you walk.
/// Everything after that is for the moment you have decided to go, or are
/// deciding whether this one is worth it.
struct DetailScreen: View {
    @Environment(ToretModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let fountain: Fountain

    /// The model's current copy: the community may have said something new since
    /// this screen was pushed, and the distance changes as the user walks.
    private var live: Fountain { model.fountains.first { $0.id == fountain.id } ?? fountain }

    private static let heroHeight: CGFloat = 300

    var body: some View {
        let fountain = live

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(for: fountain)

                PosterRule()

                VStack(alignment: .leading, spacing: 0) {
                    DetailTitle(name: fountain.place)
                        .padding(.top, 22)

                    if let line = fountain.addressLine {
                        Text(line)
                            .font(Typo.ui(15, 500))
                            .foregroundStyle(Palette.ink(0.72))
                            .padding(.top, 10)
                            .padding(.leading, 19)
                    }

                    stateRow(for: fountain)
                        .padding(.top, 20)

                    figures(for: fountain)
                        .padding(.top, 22)

                    if fountain.isSeasonal { seasonal.padding(.top, 20) }

                    sectionHeader("Comunidade")
                    CommunitySection(fountain: fountain)

                    sectionHeader("A fonte")
                    facts(for: fountain)

                    others(besides: fountain)

                    Text("Posições: \(Catalogue.attribution). O estado da água vem só dos relatos da comunidade; o Toret não mede nem garante a água.")
                        .font(Typo.ui(12.5))
                        .lineHeight(1.5, font: Typo.uiInterface(12.5))
                        .foregroundStyle(Palette.ink(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 32)
                }
                .padding(.horizontal, 22)
            }
            .padding(.bottom, Screen.tabBarClearance + 56 + 14 + 36)
        }
        .coordinateSpace(.named("detail"))
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(Debug.startsAtBottom ? .bottom : .top)
        .ignoresSafeArea()
        .overlay(alignment: .top) { topButtons(for: fountain) }
        .overlay(alignment: .bottom) { routeBar(for: fountain) }
        .background(Palette.carta)
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    // MARK: Hero

    /// The picture, bleeding under the status bar. Pulling down stretches the sky
    /// (the street stays put); scrolling up moves it at a third of the speed, so
    /// the page seems to slide over it. Both are off with Reduce Motion.
    private func hero(for fountain: Fountain) -> some View {
        let base = Self.heroHeight + Screen.safeArea.top
        return GeometryReader { proxy in
            let minY = proxy.frame(in: .named("detail")).minY
            let stretch = reduceMotion ? 0 : max(0, minY)
            let parallax = reduceMotion ? 0 : max(0, -minY) * 0.33
            ToretIllustration(kind: fountain.kind, state: fountain.state)
                .frame(width: proxy.size.width, height: base + stretch)
                .offset(y: -stretch + parallax)
        }
        .frame(height: base)
        .clipped()
    }

    /// Back and save, pinned to the screen: the way out never scrolls away. Framed
    /// circles on cream, because the picture behind them is the sun.
    private func topButtons(for fountain: Fountain) -> some View {
        let saved = model.isSaved(fountain)
        return HStack {
            circleButton(label: "Voltar") {
                Triangle().fill(Palette.inchiostro)
                    .frame(width: 13, height: 15)
                    .rotationEffect(.degrees(-90))
                    .offset(x: -1)
            } action: { dismiss() }

            Spacer()

            circleButton(label: saved ? "Remover das salvas" : "Salvar fonte") {
                ZStack {
                    Diamond().stroke(Palette.inchiostro, lineWidth: 2.5)
                    Diamond().fill(Palette.blu)
                        .scaleEffect(saved ? 1 : 0.5)
                        .opacity(saved ? 1 : 0)
                }
                .frame(width: 20, height: 20)
                .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.35), value: saved)
            } action: { model.toggleSaved(fountain) }
            .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.7), trigger: saved)
        }
        .padding(.horizontal, 18)
        .padding(.top, Screen.safeArea.top + 6)
    }

    private func circleButton<Glyph: View>(
        label: String, @ViewBuilder glyph: () -> Glyph, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            glyph()
                .frame(width: 46, height: 46)
                .background(Circle().fill(Palette.carta))
                .overlay { Circle().strokeBorder(Palette.inchiostro, lineWidth: 2.5) }
                .contentShape(Circle())
        }
        .buttonStyle(PrintPressStyle())
        .accessibilityLabel(label)
    }

    // MARK: State, figures, notices

    private func stateRow(for fountain: Fountain) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            StateMark(state: fountain.state, size: 20)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
            Text(fountain.community.sentence())
                .font(Typo.ui(17, 600))
                .foregroundStyle(Palette.inchiostro)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 19)
        .accessibilityElement(children: .combine)
    }

    /// Distance, walking time, rating: the three heavy figures, cut apart by
    /// the poster's 3 pt vertical rule.
    private func figures(for fountain: Fountain) -> some View {
        let distance = Self.distanceParts(fountain.distance)
        let rating = fountain.community.average.map {
            $0.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "pt_BR")))
        }
        let ratingCaption = fountain.community.ratingCount > 0
            ? String(localized: "\(fountain.community.ratingCount) avaliações")
            : String(localized: "sem avaliação")

        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 0) {
                figure(distance.value, unit: distance.unit, caption: String(localized: "de distância"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                verticalRule
                figure("\(fountain.walkingMinutes)", unit: "min", caption: String(localized: "a pé"))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 14)
                verticalRule
                figure(rating ?? "—", unit: nil, caption: ratingCaption)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 14)
            }
            VStack(alignment: .leading, spacing: 14) {
                figure(distance.value, unit: distance.unit, caption: String(localized: "de distância"))
                figure("\(fountain.walkingMinutes)", unit: "min", caption: String(localized: "a pé"))
                figure(rating ?? "—", unit: nil, caption: ratingCaption)
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) { PosterRule() }
        .overlay(alignment: .bottom) { PosterRule() }
    }

    private var verticalRule: some View {
        Rectangle().fill(Palette.inchiostro).frame(width: 3).frame(maxHeight: 64)
    }

    private func figure(_ value: String, unit: String?, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(Typo.display(40, 900))
                    .tracking(Typo.tracking(-0.02, at: 40))
                    .foregroundStyle(Palette.inchiostro)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(Typo.ui(14, 600))
                        .foregroundStyle(Palette.ink(0.72))
                }
            }
            Text(caption)
                .font(Typo.ui(13, 500))
                .foregroundStyle(Palette.ink(0.72))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    /// 84 m, 1,2 km. Kilometres only once metres stop being the useful unit.
    static func distanceParts(_ metres: Int) -> (value: String, unit: String) {
        guard metres >= 1000 else { return ("\(metres)", "m") }
        let km = (Double(metres) / 1000).formatted(
            .number.precision(.fractionLength(1)).locale(Locale(identifier: "pt_BR"))
        )
        return (km, "km")
    }

    private var seasonal: some View {
        Text("Fonte sazonal: costuma ser desligada no inverno, então a falta de água entre novembro e março pode não ser defeito.")
            .font(Typo.ui(14.5))
            .lineHeight(1.45, font: Typo.uiInterface(14.5))
            .foregroundStyle(Palette.inchiostro)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .plate(fill: Palette.cartaChiara, lineWidth: 2)
    }

    // MARK: Sections

    private func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PosterRule()
            Text(title)
                .font(Typo.display(24, 800))
                .foregroundStyle(Palette.inchiostro)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 34)
        .padding(.bottom, 4)
    }

    private func facts(for fountain: Fountain) -> some View {
        VStack(spacing: 0) {
            FactRow(label: "Tipo", value: fountain.kind.label)
            if let ref = fountain.ref { FactRow(label: "Número", value: ref) }
            FactRow(label: "Acessibilidade", value: fountain.wheelchair?.label ?? String(localized: "Não informado"))
            FactRow(label: "Para garrafa", value: fountain.hasBottleFiller ? String(localized: "Sim") : String(localized: "Não informado"))
            FactRow(label: "Para cães", value: fountain.allowsDogs ? String(localized: "Sim") : String(localized: "Não informado"))
            if let checked = fountain.checked {
                FactRow(label: "Posição conferida", value: checked, isLast: true)
            }
        }
    }

    /// A dry fountain is only a dead end if the screen does not say where the
    /// next one is.
    @ViewBuilder
    private func others(besides fountain: Fountain) -> some View {
        let nearby = Array(model.byDistance.filter { $0.id != fountain.id }.prefix(3))

        if !nearby.isEmpty {
            sectionHeader(fountain.state == .dry ? "Água por perto" : "Outras fontes por perto")

            VStack(spacing: 0) {
                ForEach(Array(nearby.enumerated()), id: \.element.id) { index, other in
                    Button {
                        model.select(other)
                        model.push(.detail(other), in: model.tab)
                    } label: {
                        HStack(spacing: 14) {
                            StateMark(state: other.state, size: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(other.place)
                                    .font(Typo.ui(17, 700))
                                    .foregroundStyle(Palette.inchiostro)
                                    .lineLimit(1)
                                Text("\(other.kind.label), \(other.state.label.lowercased())")
                                    .font(Typo.ui(14))
                                    .foregroundStyle(Palette.ink(0.72))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text("\(other.distance)")
                                    .font(Typo.display(28, 800))
                                    .foregroundStyle(Palette.inchiostro)
                                Text("m")
                                    .font(Typo.ui(14, 600))
                                    .foregroundStyle(Palette.ink(0.72))
                            }
                        }
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        if index < nearby.count - 1 { PosterRule(weight: .light) }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(other.place), \(other.kind.label), \(other.state.label)")
                    .accessibilityValue("\(other.distance) metros")
                }
            }
        }
    }

    // MARK: The one action

    /// Pinned over a solid base, so nothing ever shows through it, with the
    /// poster's heavy rule above. The yellow disc at the end of the button is the
    /// sun, and the triangle in it is the way forward.
    private func routeBar(for fountain: Fountain) -> some View {
        VStack(spacing: 0) {
            PosterRule()
            Button {
                model.walkingTo = fountain
            } label: {
                HStack {
                    Text("Traçar rota a pé")
                        .font(Typo.display(20, 800))
                        .foregroundStyle(Palette.carta)
                    Spacer(minLength: 8)
                    Circle().fill(Palette.sole)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Triangle().fill(Palette.inchiostro)
                                .frame(width: 11, height: 12)
                                .rotationEffect(.degrees(90))
                                .offset(x: 1)
                        }
                }
                .padding(.horizontal, 18)
                .frame(height: 56)
                .frame(maxWidth: .infinity)
                .background(Rectangle().fill(Palette.inchiostro))
                .contentShape(Rectangle())
            }
            .buttonStyle(PrintPressStyle())
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, Screen.tabBarClearance)
        }
        .background(Palette.carta)
    }
}

// MARK: - Pieces

/// The place name in the poster's type: uppercase Black, broken over two lines
/// at the most balanced word boundary, with the poster's vertical rule down its
/// left edge. The size is the largest that lets the longest line fit, so
/// "Via Po" fills the plate and "Corso Vittorio Emanuele II" still does.
struct DetailTitle: View {
    let name: String

    private static let sizes: [CGFloat] = [56, 50, 45, 40, 36, 32, 29, 26]

    var body: some View {
        let lines = Self.balancedLines(name)
        ViewThatFits(in: .horizontal) {
            ForEach(Self.sizes, id: \.self) { size in
                title(lines, size: size)
            }
            title(lines, size: 24).scaleEffect(1, anchor: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
        .accessibilityAddTraits(.isHeader)
    }

    private func title(_ lines: [String], size: CGFloat) -> some View {
        let font = Typo.uiDisplay(size, 900)
        return HStack(alignment: .top, spacing: size * 0.18) {
            Rectangle().fill(Palette.inchiostro).frame(width: 3)
            VStack(alignment: .leading, spacing: size * 0.82 - font.lineHeight) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.uppercased())
                        .font(Font(font))
                        .tracking(Typo.tracking(-0.01, at: size))
                        .foregroundStyle(Palette.inchiostro)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// One or two lines, cut where the longer of the two is shortest.
    @MainActor
    static func balancedLines(_ name: String) -> [String] {
        let words = name.split(separator: " ").map(String.init)
        guard words.count > 1 else { return [name] }
        let font = Typo.uiDisplay(40, 900)
        func width(_ text: String) -> CGFloat {
            (text.uppercased() as NSString).size(withAttributes: [.font: font]).width
        }
        var best: (width: CGFloat, split: Int) = (.infinity, 1)
        for split in 1 ..< words.count {
            let first = words[..<split].joined(separator: " ")
            let second = words[split...].joined(separator: " ")
            let longest = max(width(first), width(second))
            if longest < best.width { best = (longest, split) }
        }
        return [
            words[..<best.split].joined(separator: " "),
            words[best.split...].joined(separator: " "),
        ]
    }
}

/// A label and its value on one line, with a light rule under it.
private struct FactRow: View {
    let label: String
    let value: String
    var isLast = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(Typo.ui(15))
                .foregroundStyle(Palette.ink(0.72))
            Spacer(minLength: 0)
            Text(value)
                .font(Typo.ui(15, 600))
                .foregroundStyle(Palette.inchiostro)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            if !isLast { PosterRule(weight: .light) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A press that moves the plate two points down and right, like a hand-pulled
/// print slipping off register, instead of dimming or glowing.
private struct PrintPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? 2 : 0)
            .animation(reduceMotion ? nil : .spring(duration: 0.2, bounce: 0), value: configuration.isPressed)
    }
}
