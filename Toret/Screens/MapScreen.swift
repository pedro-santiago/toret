import MapKit
import SwiftUI

/// The map: Turin as Apple draws it, the fountains on it, and the needle that
/// never leaves the screen.
///
/// The basemap is MapKit — real streets, real squares, real scale, and it keeps
/// working when you walk off the edge of the twelve fountains in this build.
/// Points of interest are turned off: every café pin the system would add is a
/// pin competing with the only three colours this app has anything to say with.
struct MapScreen: View {
    @Environment(ToretModel.self) private var model
    @Environment(LocationProvider.self) private var location

    /// Lets the search field and its chips behave as one body of glass.
    @Namespace private var glass

    var body: some View {
        @Bindable var model = model

        // The map bleeds under the status bar and the tab bar; the glass is
        // positioned against the display's real edges, read from the window.
        // See ``Screen`` for why the insets are not taken from the hierarchy.
        ZStack(alignment: .top) {
            Map(position: $model.camera) {
                UserAnnotation()

                ForEach(model.mapLandmarks) { landmark in
                    Annotation(landmark.name, coordinate: landmark.coordinate, anchor: .center) {
                        LandmarkMarker(landmark: landmark)
                    }
                    .annotationTitles(.hidden)
                }

                ForEach(model.mapPins) { fountain in
                    Annotation(fountain.place, coordinate: fountain.coordinate, anchor: .center) {
                        FountainPin(
                            fountain: fountain,
                            isSelected: fountain == model.selected,
                            isDimmed: !model.matchesFilters(fountain),
                            token: model.selectionToken
                        ) {
                            model.select(fountain)
                        }
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .onEnd) { context in
                model.visibleRegion = context.region
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            // A plaster cast over Apple's map, so it sits in the same light as
            // the rest of the app instead of next to it.
            .colorMultiply(Palette.mapWash)

            topControls(searchText: $model.searchText)
                .padding(.top, Screen.safeArea.top + 8)

            bottomControls()
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, Screen.tabBarClearance + 10)
        }
        // Applied to the stack rather than to the map, so every child is laid
        // out in one frame that spans the display and the paddings above are
        // measured from its physical edges.
        .ignoresSafeArea()
    }

    // MARK: Glass floating over it

    private func topControls(searchText: Binding<String>) -> some View {
        ToretGlassGroup(spacing: 14) {
            VStack(alignment: .leading, spacing: 9) {
                SearchPill(text: searchText)
                    .glassEffectID("search", in: glass)
                FilterChips(active: model.activeFilters) { model.toggle($0) }
                if model.searchText.count >= 2 {
                    SearchResults()
                } else {
                    LocationBanner(status: location.status)
                }
            }
        }
        .padding(.horizontal, 14)
        .animation(Motion.ui, value: location.status)
    }

    private func bottomControls() -> some View {
        VStack(spacing: 12) {
            CompassPill(
                fountain: model.selected,
                needleAngle: model.needleAngle,
                token: model.selectionToken,
                isNearest: model.selectedIsNearest
            ) {
                model.showingCompass = true
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 2)

            SelectedFountainCard()
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - The sheet

/// What the map says about the fountain you have chosen: the two numbers that
/// decide whether you walk, and the state of the water when someone last looked.
struct SelectedFountainCard: View {
    @Environment(ToretModel.self) private var model

    private var fountain: Fountain { model.selected }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Palette.ink.opacity(0.18))
                .frame(width: 38, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)

            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "Selecionada")
                Spacer()
                Text("\(model.withinHalfKilometre) fontes em 500 m")
                    .font(Typo.ui(11, 500))
                    .foregroundStyle(Palette.ink.opacity(0.5))
            }
            .padding(.bottom, 4)

            Button {
                model.push(.detail(fountain), in: .map)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    DisplayText(
                        fountain.place, size: 27, leading: 1.15,
                        tracking: Typo.tracking(-0.01, at: 27)
                    )
                    Text("\(fountain.plateTitle) · \(fountain.zone)")
                        .font(Typo.displayItalic(13))
                        .foregroundStyle(Palette.ink.opacity(0.62))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Abre o detalhe da fonte")

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        CountingMetres(
                            metres: fountain.distance, token: model.selectionToken,
                            size: 20, color: Palette.green
                        )
                        Text("m").font(Typo.display(20)).foregroundStyle(Palette.green)
                    }
                    Text("DISTÂNCIA")
                        .font(Typo.narrow(8.5))
                        .tracking(Typo.tracking(0.12, at: 8.5))
                        .foregroundStyle(Palette.ink.opacity(0.5))
                }

                StatDivider()
                StatBlock(value: "\(fountain.walkingMinutes) min", caption: "A PÉ")
                StatDivider()
                StatBlock(
                    value: fountain.state.label,
                    caption: fountain.community.provenance,
                    valueColor: fountain.state.color,
                    isProse: true
                )
            }
            .padding(.vertical, 11)
            .overlay(alignment: .top) { hairline }
            .overlay(alignment: .bottom) { hairline }
            .padding(.top, 13)
            .padding(.bottom, 15)

            HStack(spacing: 9) {
                PrimaryButton(title: "Traçar rota", height: 50, fontSize: 15) {
                    model.walkingTo = fountain
                }
                GlyphButton(
                    diameter: 50,
                    accessibilityText: model.isSaved(fountain)
                        ? "Remover das salvas" : "Salvar fonte"
                ) {
                    IconView(
                        shape: Icon.Lozenge(), size: 17,
                        tint: model.isSaved(fountain) ? Palette.green : Palette.ink,
                        filled: model.isSaved(fountain)
                    )
                } action: {
                    model.toggleSaved(fountain)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .glassPane(cornerRadius: 28, tone: .paper)
    }

    private var hairline: some View {
        Rectangle().fill(Palette.ink.opacity(0.1)).frame(height: 1)
    }
}
