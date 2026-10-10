import MapKit
import SwiftUI

/// Walking.
///
/// One instruction, set large enough to read at arm's length while moving, and
/// nothing competing with it. Everything else — the arrival time, the remaining
/// metres, the step after this one — is demoted to the card at the bottom, where
/// you look only when you stop.
struct RouteScreen: View {
    @Environment(ToretModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let fountain: Fountain

    /// Starts as the straight line and is replaced when MapKit answers, so the
    /// screen is useful the instant it appears rather than after a spinner.
    @State private var route: WalkingRoute
    @State private var camera: MapCameraPosition
    /// Where the current route was worked out from, so the screen can tell how
    /// far the user has walked away from its own answer.
    @State private var routedFrom: CLLocationCoordinate2D?
    @State private var isRouting = false

    init(fountain: Fountain) {
        self.fountain = fountain
        _route = State(initialValue: WalkingRoute(to: fountain))
        _camera = State(initialValue: .region(
            MKCoordinateRegion(
                center: fountain.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
            )
        ))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $camera) {
                UserAnnotation()

                if let polyline = route.polyline {
                    MapPolyline(polyline)
                        .stroke(
                            Palette.green,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                        )
                }

                Annotation(fountain.place, coordinate: fountain.coordinate, anchor: .center) {
                    FountainPin(
                        fountain: fountain, isSelected: true,
                        token: model.selectionToken
                    ) {}
                }
                .annotationTitles(.hidden)
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .colorMultiply(Palette.mapWash)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                instruction
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                Spacer()
                progress
                    .padding(.horizontal, 12)
                PrimaryButton(
                    title: "Encerrar rota", height: 48, fontSize: 15,
                    background: Palette.ink.opacity(0.9)
                ) {
                    dismiss()
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, Screen.safeArea.bottom + 4)
            }
            .padding(.top, Screen.safeArea.top + 8)
        }
        .ignoresSafeArea()
        .task { await recompute(reframing: true) }
        // A turn-by-turn screen that answers once and then goes quiet is worse
        // than a straight line: it keeps naming a turn you already took.
        .onChange(of: model.origin.latitude) { refreshIfMoved() }
        .onChange(of: model.origin.longitude) { refreshIfMoved() }
    }

    /// Re-asks MapKit for the walk from where the user is now.
    ///
    /// Only the first answer frames the camera. Reframing on every fix would
    /// snatch the map back each time the user panned it to look ahead.
    private func recompute(reframing: Bool) async {
        guard !isRouting else { return }
        isRouting = true
        defer { isRouting = false }

        let from = model.origin
        let walked = await WalkingRoute.directions(from: from, to: fountain)
        withAnimation(Motion.ui) {
            route = walked
            if reframing, let polyline = walked.polyline {
                // Frame the whole walk, with room for the two cards over it.
                camera = .rect(polyline.boundingMapRect)
            }
        }
        routedFrom = from
    }

    /// Twenty-five metres is about a third of a Turin block: far enough that the
    /// instruction may have changed, close enough that it changes before you
    /// have walked past the turn. It also keeps the directions requests down to
    /// one every twenty seconds or so at walking pace.
    private func refreshIfMoved() {
        guard let routedFrom, !isRouting else { return }
        let walked = CLLocation(
            latitude: routedFrom.latitude, longitude: routedFrom.longitude
        ).distance(
            from: CLLocation(
                latitude: model.origin.latitude, longitude: model.origin.longitude
            )
        )
        guard walked >= 25 else { return }
        Task { await recompute(reframing: false) }
    }

    // MARK: The one thing to do next

    private var instruction: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Eyebrow(
                    text: "A pé até a \(fountain.plateTitle.lowercased())",
                    color: Palette.brass
                )
                Spacer()
                Button { dismiss() } label: {
                    IconView(shape: Icon.Lozenge(), size: 11, weight: 2, tint: Palette.paperRaised)
                        .frame(width: 30, height: 30)
                        .background { Circle().fill(Palette.paperRaised.opacity(0.14)) }
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Encerrar rota")
            }

            HStack(alignment: .bottom, spacing: 12) {
                CountingMetres(
                    metres: route.toNextTurn, token: route.remaining,
                    size: 54, color: Palette.paperRaised
                )
                Text("m")
                    .font(Typo.ui(15, 500))
                    .foregroundStyle(Palette.paperRaised.opacity(0.6))
                    .padding(.bottom, 9)
            }
            .padding(.top, 12)

            Text(route.headline)
                .font(Typo.ui(21, 500))
                .lineHeight(1.25, font: Typo.uiInterface(21, 500))
                .foregroundStyle(Palette.paperRaised)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Text(route.subhead)
                .font(Typo.ui(13.5))
                .foregroundStyle(Palette.paperRaised.opacity(0.6))
                .lineLimit(2)
                .padding(.top, 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Palette.ink)
                .shadow(color: Palette.ink.opacity(0.28), radius: 17, y: 10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(route.toNextTurn) metros. \(route.headline). \(route.subhead)")
    }

    // MARK: Where you are in the walk

    private var progress: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                StatBlock(
                    value: "\(route.minutes) min", caption: "CHEGADA \(route.arrival())",
                    valueColor: Palette.green, size: 24
                )
                StatBlock(value: "\(route.remaining) m", caption: "RESTANTES", size: 24)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Palette.ink.opacity(0.1)).frame(height: 1)
            }

            VStack(spacing: 0) {
                ForEach(Array(route.steps.enumerated()), id: \.element.id) { index, step in
                    HStack(spacing: 13) {
                        ZStack {
                            Circle().fill(Palette.green.opacity(0.12))
                            switch step.kind {
                            case .turn:
                                IconView(
                                    shape: Icon.TurnRight(), size: 12,
                                    weight: 1.7, tint: Palette.green
                                )
                            case .arrive:
                                Circle().fill(Palette.green).frame(width: 8, height: 8)
                            }
                        }
                        .frame(width: 22, height: 22)

                        Text(step.instruction)
                            .font(Typo.ui(14))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if step.distance > 0 {
                            Text("\(step.distance) m")
                                .font(Typo.ui(13, 500))
                                .foregroundStyle(Palette.ink.opacity(0.5))
                        }
                    }
                    .padding(.vertical, 11)
                    .overlay(alignment: .bottom) {
                        if index < route.steps.count - 1 {
                            Rectangle().fill(Palette.ink.opacity(0.07)).frame(height: 1)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .glassPane(cornerRadius: 22, tone: .paper)
    }
}
