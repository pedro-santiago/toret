import SwiftUI

/// One fountain, at length.
///
/// The design's own note, kept: the state of the water and the provenance of that
/// reading are the two things this screen exists for. "Água corrente · verificado
/// hoje" is a claim, and the last four rows are what backs it — when it was
/// checked, and who says so. A fountain app that reports a state without saying
/// where the state came from is asking to be trusted for nothing.
struct DetailScreen: View {
    @Environment(ToretModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let fountain: Fountain

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FountainPlate(fountain: fountain, onBack: { dismiss() }, onSave: {
                    model.toggleSaved(fountain)
                }, isSaved: model.isSaved(fountain))

                ArcadeCornice(height: 13)
                    .padding(.horizontal, 22)
                    .padding(.top, 12)

                body(in: fountain)
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
            }
            .padding(.bottom, Screen.tabBarClearance + 130)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(Debug.startsAtBottom ? .bottom : .top)
        .ignoresSafeArea()
        .overlay(alignment: .bottom) { actions }
        .background(Palette.paper)
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func body(in fountain: Fountain) -> some View {
        Eyebrow(text: "\(fountain.plateTitle) · \(fountain.zone)")

        DisplayText(
            fountain.titleLines,
            size: 38, leading: 1.05, tracking: Typo.tracking(-0.015, at: 38)
        )
        .padding(.top, 7)

        if let subtitle = fountain.addressLine {
            Text(subtitle)
                .font(Typo.displayItalic(14))
                .foregroundStyle(Palette.ink.opacity(0.62))
                .padding(.top, 6)
        }

        StatusChip(
            state: fountain.state,
            text: "\(fountain.state.label) · \(fountain.community.provenance.capitalized)"
        )
        .padding(.top, 14)

        HStack(spacing: 22) {
            StatBlock(
                value: "\(fountain.distance) m", caption: "DISTÂNCIA",
                valueColor: Palette.green, size: 26
            )
            StatBlock(value: "\(fountain.walkingMinutes) min", caption: "A PÉ", size: 26)
            StatBlock(
                value: fountain.community.average.map {
                    $0.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "pt_BR")))
                } ?? "—",
                caption: "AVALIAÇÃO", size: 26
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .overlay(alignment: .top) { hairline }
        .overlay(alignment: .bottom) { hairline }
        .padding(.top, 22)

        if fountain.isSeasonal {
            Text("Fonte sazonal: costuma ser desligada no inverno, então a falta de água entre novembro e março pode não ser defeito.")
                .font(Typo.ui(13.5))
                .lineHeight(1.5, font: Typo.uiInterface(13.5))
                .foregroundStyle(Palette.ink.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }

        sectionHeader("Comunidade")
        CommunitySection(fountain: fountain)

        section("A fonte") {
            SpecRow(label: "Tipo", value: fountain.kind.label)
            if let ref = fountain.ref { SpecRow(label: "Número", value: ref) }
            SpecRow(label: "Acessibilidade", value: fountain.wheelchair?.label ?? "Não informado")
            SpecRow(label: "Para garrafa", value: fountain.hasBottleFiller ? "Sim" : "Não informado")
            SpecRow(label: "Para cães", value: fountain.allowsDogs ? "Sim" : "Não informado")
            if let checked = fountain.checked { SpecRow(label: "Posição conferida", value: checked) }
        }

        others(besides: fountain)

        Text("Posições: \(Catalogue.attribution). O estado da água vem só dos relatos da comunidade; o Toret não mede nem garante a água.")
            .font(Typo.ui(11.5))
            .lineHeight(1.5, font: Typo.uiInterface(11.5))
            .foregroundStyle(Palette.ink.opacity(0.45))
            .padding(.top, 28)
    }

    /// The fallback. A dry fountain is only a dead end if the screen does not
    /// say where the next one is.
    @ViewBuilder
    private func others(besides fountain: Fountain) -> some View {
        let nearby = model.byDistance.filter { $0 != fountain }.prefix(3)

        sectionHeader(fountain.state == .dry ? "Água por perto" : "Outras fontes por perto")

        VStack(spacing: 0) {
            ForEach(Array(nearby)) { other in
                Button {
                    model.select(other)
                    model.push(.detail(other), in: model.tab)
                } label: {
                    HStack(spacing: 12) {
                        Needle.row(
                            angle: other.bearing,
                            tint: other.state.color,
                            stem: Palette.ink.opacity(0.2),
                            diameter: 20
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(other.place)
                                .font(Typo.ui(14.5, 500))
                                .foregroundStyle(Palette.ink)
                            Text(other.state.label)
                                .font(Typo.ui(12))
                                .foregroundStyle(Palette.ink.opacity(0.5))
                        }
                        Spacer(minLength: 0)
                        Text("\(other.distance) m")
                            .font(Typo.display(17))
                            .foregroundStyle(Palette.ink.opacity(0.75))
                    }
                    .padding(.vertical, 11)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) {
                    if other != nearby.last {
                        Rectangle().fill(Palette.ink.opacity(0.08)).frame(height: 1)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(other.place), \(other.state.label), \(other.distance) metros")
            }
        }
    }

    /// A lozenge rule, a narrow-caps heading, and the rows under it.
    @ViewBuilder
    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        sectionHeader(title)
        VStack(spacing: 0) { content() }
    }

    private func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            LozengeRule()
            Text(title.uppercased())
                .font(Typo.narrow(9.5))
                .tracking(Typo.tracking(0.14, at: 9.5))
                .foregroundStyle(Palette.ink.opacity(0.5))
        }
        .padding(.top, 26)
        .padding(.bottom, 2)
    }

    private var hairline: some View {
        Rectangle().fill(Palette.ink.opacity(0.12)).frame(height: 1)
    }

    private var actions: some View {
        PrimaryButton(title: "Traçar rota a pé") {
            model.walkingTo = fountain
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, Screen.tabBarClearance)
        .background {
            // The fade runs all the way down behind the tab bar; stopping it at
            // the buttons leaves specification rows showing through underneath.
            LinearGradient(
                stops: [
                    .init(color: Palette.paper.opacity(0), location: 0),
                    .init(color: Palette.paper, location: 0.3),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }
}

// MARK: - The plate

/// Where the photograph goes.
///
/// Until there is one, the fountain is drawn: the cast-iron column, the collar,
/// the spout, and the setts it stands on. A grey box would say "missing"; this
/// says "a toret", which is the thing the reader is about to look for in the
/// street.
struct FountainPlate: View {
    let fountain: Fountain
    let onBack: () -> Void
    let onSave: () -> Void
    let isSaved: Bool

    /// Header height, measured from its foot upwards like the design does.
    ///
    /// The design drew it 302 pt tall on a flat status bar. Trimmed here: on a
    /// real screen the two pinned buttons take the bottom 160 pt, and the plate
    /// has to give up enough room for the distance and the walk to stay above
    /// the fold — those are the numbers the screen exists to answer.
    private static let height: CGFloat = 270

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: Palette.plateHighlight, location: 0),
                            .init(color: Palette.plateMid, location: 0.58),
                            .init(color: Palette.plateShadow, location: 1),
                        ],
                        center: .top, startRadius: 0, endRadius: 340
                    )
                )
                .overlay { CrossHatch(spacing: 15).stroke(Palette.ink.opacity(0.05), lineWidth: 1) }

            // The column, its collar, and the spout — stacked from the ground up.
            arch(width: 150, height: 176, radius: 75)
                .fill(
                    LinearGradient(
                        colors: [Palette.plateStone, Palette.plateStoneDeep],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay { arch(width: 150, height: 176, radius: 75).stroke(Palette.ink.opacity(0.24), lineWidth: 1.5) }
                .frame(width: 150, height: 176)
                .padding(.bottom, 50)

            arch(width: 106, height: 134, radius: 53)
                .stroke(Palette.ink.opacity(0.18), lineWidth: 1)
                .frame(width: 106, height: 134)
                .padding(.bottom, 50)

            // The one terracotta mark on the plate, where the water comes out.
            Circle()
                .fill(Palette.plateHighlight)
                .overlay { Circle().strokeBorder(Palette.terracotta.opacity(0.55), lineWidth: 1.5) }
                .frame(width: 18, height: 18)
                .padding(.bottom, 200)

            setts

        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .topLeading) {
            plateButton(accessibility: "Voltar") {
                Chevron()
                    .stroke(Palette.ink, style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: 9, height: 15)
            } action: { onBack() }
            .padding(.leading, 14)
            .padding(.top, Screen.safeArea.top + 4)
        }
        .overlay(alignment: .topTrailing) {
            plateButton(accessibility: isSaved ? "Remover das salvas" : "Salvar fonte") {
                IconView(
                    shape: Icon.Lozenge(), size: 15, weight: 1.9,
                    tint: isSaved ? Palette.green : Palette.ink, filled: isSaved
                )
            } action: { onSave() }
            .padding(.trailing, 14)
            .padding(.top, Screen.safeArea.top + 4)
        }
        .accessibilityElement(children: .contain)
    }

    /// A round-headed column: a rectangle whose top is a true semicircle, which
    /// is the profile of a toret seen straight on.
    private func arch(width: CGFloat, height: CGFloat, radius: CGFloat) -> some Shape {
        UnevenRoundedRectangle(
            topLeadingRadius: radius, bottomLeadingRadius: 0,
            bottomTrailingRadius: 0, topTrailingRadius: radius, style: .circular
        )
    }

    /// The setts the fountain stands on.
    private var setts: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11.5) {
                ForEach(0 ..< 34, id: \.self) { _ in
                    Rectangle().fill(Palette.ink.opacity(0.24)).frame(width: 1.5)
                }
            }
            .frame(height: 15)
            .frame(maxWidth: .infinity)
            .clipped()

            Rectangle().fill(Palette.ink.opacity(0.2)).frame(height: 1.5)
        }
        .padding(.bottom, 30)
        .accessibilityHidden(true)
    }

    private func plateButton<G: View>(
        accessibility: String,
        @ViewBuilder glyph: () -> G,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            glyph()
                .frame(width: 40, height: 40)
                .glassPane(Circle(), tone: .paper, interactive: true)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(accessibility)
    }
}

/// A 45° crosshatch — the grain of a plaster wall, and of a photograph that is
/// not there yet.
struct CrossHatch: Shape {
    var spacing: CGFloat = 15

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let reach = rect.width + rect.height
        var offset = -reach
        while offset <= reach {
            path.move(to: CGPoint(x: rect.minX + offset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + offset + rect.height, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX + offset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + offset + rect.height, y: rect.minY))
            offset += spacing
        }
        return path
    }
}
