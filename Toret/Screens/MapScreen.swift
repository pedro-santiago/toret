import MapKit
import SwiftUI

/// The map: Turin as Apple draws it, printed on cream, with the fountains marked
/// in the poster's shapes and a black plate that says what you are looking at.
///
/// The basemap is MapKit — real streets, real squares, real scale — pulled onto the
/// stock with a flat wash so the roads print in the same light as the rest of the
/// app. Points of interest are off: every café pin the system would add competes
/// with the only marks this app has anything to say with.
///
/// What is drawn depends on how far out you are (see ``PinDensity``): full state
/// marks at street level, small ones across a neighbourhood, and across the whole
/// city dots with numbered badges where dots would touch.
struct MapScreen: View {
    @Environment(ToretModel.self) private var model
    @Environment(LocationProvider.self) private var location
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // A catalogue that did not load leaves nothing to select; say so plainly
        // rather than indexing into an empty list.
        if model.fountains.isEmpty {
            CatalogueMissing()
        } else {
            content
        }
    }

    // MARK: Layout

    private var content: some View {
        @Bindable var model = model
        let span = model.visibleRegion?.span.latitudeDelta ?? 0.011
        let density = PinDensity(latitudeSpan: span)
        let items = pinItems(span: span)

        // The map bleeds under the status bar and the tab bar; the plates are
        // positioned against the display's real edges, read from the window.
        // See ``Screen`` for why the insets are not taken from the hierarchy.
        return ZStack(alignment: .top) {
            Map(position: $model.camera) {
                UserAnnotation { UserMark() }

                if density != .dot {
                    ForEach(model.mapLandmarks) { landmark in
                        Annotation(landmark.name, coordinate: landmark.coordinate, anchor: .center) {
                            LandmarkMarker(landmark: landmark)
                        }
                        .annotationTitles(.hidden)
                    }
                }

                ForEach(items) { item in
                    switch item {
                    case let .fountain(fountain):
                        Annotation(fountain.place, coordinate: fountain.coordinate, anchor: .center) {
                            FountainPin(
                                fountain: fountain,
                                isSelected: fountain == model.selected,
                                isDimmed: !model.matchesFilters(fountain),
                                density: density,
                                token: model.selectionToken
                            ) {
                                model.select(fountain)
                            }
                        }
                        .annotationTitles(.hidden)
                    case let .cluster(cluster):
                        Annotation("", coordinate: cluster.coordinate, anchor: .center) {
                            ClusterBadge(cluster: cluster) { zoom(into: cluster) }
                        }
                        .annotationTitles(.hidden)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .onEnd) { context in
                model.visibleRegion = context.region
            }
            .mapControlVisibility(.hidden)
            // Stock over Apple's map, so it sits in the same light as the rest of
            // the app instead of next to it.
            .colorMultiply(Palette.mapWash)

            topControls(searchText: $model.searchText)
                .padding(.top, Screen.safeArea.top + 8)

            bottomControls(isEmpty: items.isEmpty)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, Screen.tabBarClearance + 10)
        }
        // Applied to the stack rather than to the map, so every child is laid
        // out in one frame that spans the display and the paddings above are
        // measured from its physical edges.
        .ignoresSafeArea()
    }

    /// What to draw for the current view: the fountains in it, folded into
    /// badges when the map is wide, with the selected one always present.
    private func pinItems(span: Double) -> [PinItem] {
        var visible = PinLayout.visible(model.fountains, in: model.visibleRegion)
        let selected = model.selected
        if !visible.contains(selected) { visible.append(selected) }
        let pinned = Set(model.savedIDs).union([selected.id])
        return PinLayout.items(for: visible, latitudeSpan: span, pinned: pinned)
    }

    private func zoom(into cluster: PinCluster) {
        withAnimation(reduceMotion ? nil : Motion.ui) {
            model.camera = .region(cluster.zoomRegion)
        }
    }

    // MARK: Plates over the map

    private func topControls(searchText: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SearchPill(text: searchText)
            FilterChips(active: model.activeFilters) { model.toggle($0) }
            if model.searchText.count >= 2 {
                SearchResults()
            } else {
                LocationBanner(status: location.status)
            }
        }
        .padding(.horizontal, 14)
        .animation(reduceMotion ? nil : Motion.ui, value: location.status)
    }

    private func bottomControls(isEmpty: Bool) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom) {
                MapCompassButton(
                    fountain: model.selected,
                    needleAngle: model.needleAngle,
                    token: model.selectionToken,
                    isNearest: model.selectedIsNearest
                ) {
                    model.showingCompass = true
                }
                Spacer(minLength: 0)
                MapRoundButton(label: String(localized: "Voltar para onde estou")) {
                    TargetGlyph()
                } action: {
                    recentre()
                }
            }

            if isEmpty { NoFountainsHere(onNearest: showNearest) }

            SelectedFountainCard()
        }
        .padding(.horizontal, 12)
    }

    /// Back to where the user is — or, when the app is not measuring from them
    /// (no permission, outside Turin), to the nearest fountain, which is the
    /// closest honest answer.
    private func recentre() {
        if location.status.isMeasuringFromUser {
            withAnimation(reduceMotion ? nil : Motion.ui) {
                model.camera = .region(
                    MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                    )
                )
            }
        } else {
            showNearest()
        }
    }

    private func showNearest() {
        guard let nearest = model.nearestUsable(1).first ?? model.fountains.first else { return }
        if nearest == model.selected {
            withAnimation(reduceMotion ? nil : Motion.ui) {
                model.camera = .region(
                    MKCoordinateRegion(
                        center: nearest.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.009, longitudeDelta: 0.009)
                    )
                )
            }
        } else {
            withAnimation(reduceMotion ? nil : Motion.ui) { model.select(nearest) }
        }
    }
}

// MARK: - You are here

/// The user's own position: a black disc ringed in stock, with a second ring round
/// it. Deliberately not the system's blue dot — blue is running water here.
struct UserMark: View {
    var body: some View {
        ZStack {
            Circle().strokeBorder(Palette.inchiostro, lineWidth: 2).frame(width: 30, height: 30)
            Circle().fill(Palette.inchiostro).frame(width: 14, height: 14)
            Circle().strokeBorder(Palette.carta, lineWidth: 3).frame(width: 14, height: 14)
        }
        .accessibilityLabel("Você está aqui")
    }
}

// MARK: - Edge cases

/// The map's empty moment: nothing in view, and one way out of it.
struct NoFountainsHere: View {
    let onNearest: () -> Void

    var body: some View {
        EmptyScene(
            kind: .noPins, layout: .row,
            actionTitle: String(localized: "Ir para a mais próxima"), action: onNearest
        )
        .padding(12)
        .plate()
    }
}

/// What the map shows when the bundled catalogue could not be read: a build
/// fault, not something the user can fix, so it says what happened and stops.
struct CatalogueMissing: View {
    var body: some View {
        ZStack {
            Palette.carta.ignoresSafeArea()
            EmptyScene(kind: .catalogueFailed)
        }
    }
}

// MARK: - The plate

/// What the map says about the fountain you have chosen: its name, how far it is,
/// and what the community last said about the water — set as one printed plate.
struct SelectedFountainCard: View {
    @Environment(ToretModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var figureSize: CGFloat = 56

    private var fountain: Fountain { model.selected }

    var body: some View {
        let lines = StateSentence.lines(for: fountain.community)
        let saved = model.isSaved(fountain)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.selectedIsNearest ? String(localized: "Fonte mais próxima") : String(localized: "Fonte selecionada"))
                    .font(Typo.ui(12.5, 600))
                    .foregroundStyle(Palette.ink(0.75))
                Spacer(minLength: 8)
                Text("\(model.withinHalfKilometre) fontes em 500 m")
                    .font(Typo.ui(12.5, 500))
                    .foregroundStyle(Palette.ink(0.75))
            }
            .padding(.bottom, 8)

            Button {
                model.push(.detail(fountain), in: .map)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(fountain.place)
                        .font(Typo.display(28, 800))
                        .foregroundStyle(Palette.inchiostro)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.leading)
                    Text("\(fountain.plateTitle), \(fountain.zone)")
                        .font(Typo.ui(14, 500))
                        .foregroundStyle(Palette.ink(0.75))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Abre o detalhe da fonte")

            PosterRule()
                .padding(.vertical, 12)

            ViewThatFits(in: .horizontal) {
                figures(lines: lines, stacked: false)
                figures(lines: lines, stacked: true)
            }
            .padding(.bottom, 14)

            HStack(spacing: 10) {
                PosterActionButton(title: String(localized: "Traçar rota")) {
                    model.walkingTo = fountain
                }
                Button { model.toggleSaved(fountain) } label: {
                    IconView(
                        shape: Icon.Lozenge(), size: 20, weight: 2.4,
                        tint: Palette.inchiostro, filled: saved
                    )
                    .frame(width: 56, height: 56)
                    .overlay { Rectangle().strokeBorder(Palette.inchiostro, lineWidth: 2.5) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .sensoryFeedback(.success, trigger: saved)
                .accessibilityLabel(saved ? String(localized: "Remover das salvas") : String(localized: "Salvar fonte"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .plate()
        .animation(reduceMotion ? nil : Motion.ui, value: fountain.id)
    }

    /// The big figure and, beside it, what is known about the water. Falls back
    /// to a stack when Dynamic Type makes the row too wide.
    @ViewBuilder
    private func figures(lines: (headline: String, detail: String), stacked: Bool) -> some View {
        let distance = VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                CountingMetres(
                    metres: fountain.distance, token: model.selectionToken,
                    size: min(figureSize, 84), weight: 900, color: Palette.inchiostro,
                    tracking: Typo.tracking(-0.02, at: 56)
                )
                Text("m")
                    .font(Typo.ui(18, 700))
                    .foregroundStyle(Palette.inchiostro)
            }
            Text("\(fountain.walkingMinutes) min a pé")
                .font(Typo.ui(14, 600))
                .foregroundStyle(Palette.ink(0.8))
        }
        let water = VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                StateMark(state: fountain.state, size: 22)
                Text(lines.headline)
                    .font(Typo.ui(15, 700))
                    .foregroundStyle(Palette.inchiostro)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(lines.detail)
                .font(Typo.ui(13))
                .foregroundStyle(Palette.ink(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }

        if stacked {
            VStack(alignment: .leading, spacing: 10) { distance; water }
        } else {
            HStack(alignment: .center, spacing: 14) {
                distance
                Rectangle().fill(Palette.inchiostro).frame(width: 3, height: 52)
                water
                Spacer(minLength: 0)
            }
        }
    }
}
