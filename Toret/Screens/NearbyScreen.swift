import SwiftUI

/// Perto de mim — the same fountains as the map, sorted by the only thing that
/// decides anything on foot.
///
/// Each row keeps its needle, so the list is still a compass: you can see that
/// the nearest one is behind you and the second-nearest is straight ahead before
/// you open either.
struct NearbyScreen: View {
    @Environment(ToretModel.self) private var model

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.horizontal, 22)

                    LazyVStack(spacing: 0) {
                        ForEach(model.nearest7) { fountain in
                            FountainRow(
                                fountain: fountain,
                                needleAngle: fountain.bearing,
                                token: model.selectionToken,
                                isSelected: fountain == model.selected,
                                isDimmed: !model.matchesFilters(fountain)
                            ) {
                                model.select(fountain)
                                model.push(.detail(fountain), in: .nearby)
                            }
                        }
                    }
                    .padding(.top, 22)
                }
            .padding(.bottom, Screen.tabBarClearance + 86)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .bottom) {
            seeOnMap.padding(.bottom, Screen.tabBarClearance)
        }
        .background(Palette.paper)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Torino · centro")

            DisplayText(
                "Perto de mim", size: 40, leading: 1,
                tracking: Typo.tracking(-0.015, at: 40)
            )
            .padding(.top, 8)

            Text("\(model.withinHalfKilometre) fontes em 500 m · atualizado às \(Date.now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "pt_BR"))))")
                .font(Typo.ui(13.5))
                .foregroundStyle(Palette.ink.opacity(0.6))
                .padding(.top, 8)

            LozengeTicks()
                .padding(.top, 16)
        }
        .padding(.top, 12)
    }

    private var seeOnMap: some View {
        PrimaryButton(
            title: "Ver no mapa", height: 50, fontSize: 15,
            background: Palette.ink, leadingDot: Palette.sage
        ) {
            model.popToRoot(.nearby)
            model.tab = .map
        }
        .padding(.horizontal, 22)
        .padding(.top, 30)
        .padding(.bottom, 12)
        .background {
            // A long fade, so a row sliding under the button dissolves into the
            // plaster instead of being sliced by it.
            LinearGradient(
                stops: [
                    .init(color: Palette.paper.opacity(0), location: 0),
                    .init(color: Palette.paper, location: 0.55),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }
}

/// Salvas — the fountains a resident walks past every day.
///
/// The design's second audience: someone who does not need a map of the centre,
/// only the four fountains on their own route, and whether they are running today.
struct SavedScreen: View {
    @Environment(ToretModel.self) private var model

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Eyebrow(text: "As suas fontes")
                        DisplayText(
                            "Salvas", size: 40, leading: 1,
                            tracking: Typo.tracking(-0.015, at: 40)
                        )
                        .padding(.top, 8)
                        Text(model.savedFountains.isEmpty
                            ? "Nenhuma fonte salva ainda"
                            : "\(model.savedFountains.count) no seu trajeto")
                            .font(Typo.ui(13.5))
                            .foregroundStyle(Palette.ink.opacity(0.6))
                            .padding(.top, 8)
                        LozengeTicks().padding(.top, 16)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 12)

                    if model.savedFountains.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(model.savedFountains) { fountain in
                                FountainRow(
                                    fountain: fountain,
                                    needleAngle: fountain.bearing,
                                    token: model.selectionToken,
                                    isSelected: fountain == model.selected
                                ) {
                                    model.select(fountain)
                                    model.push(.detail(fountain), in: .saved)
                                }
                            }
                        }
                        .padding(.top, 22)
                    }
                }
            .padding(.bottom, Screen.tabBarClearance + 24)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .bottom)
        .background(Palette.paper)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Lozenge(size: 18, filled: false, color: Palette.ink.opacity(0.25), lineWidth: 2)
            Text("Toque no losango numa fonte para guardá-la aqui.")
                .font(Typo.ui(14))
                .foregroundStyle(Palette.ink.opacity(0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}
