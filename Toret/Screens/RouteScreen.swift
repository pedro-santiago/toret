import MapKit
import SwiftUI

/// Walking.
///
/// The instruction is the poster: the metres to the next turn, set as large as
/// the plate allows, with one plain line under it. Everything else — the arrival
/// time, the metres left, the steps after this one — is demoted to the plate at
/// the bottom, where you look only when you stop.
struct RouteScreen: View {
    @Environment(ToretModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var figureSize: CGFloat = 120

    let fountain: Fountain

    /// Starts as the straight line and is replaced when MapKit answers, so the
    /// screen is useful the instant it appears rather than after a spinner.
    @State private var route: WalkingRoute
    @State private var camera: MapCameraPosition
    /// Where the current route was worked out from, so the screen can tell how
    /// far the user has walked away from its own answer.
    @State private var routedFrom: CLLocationCoordinate2D?
    @State private var isRouting = false
    /// True once MapKit has answered — or failed to — at least once, so the
    /// straight-line fallback is only announced after we really tried.
    @State private var hasAnswered = false

    /// Closer than this and you are there. A fountain is a fountain, not a point:
    /// twenty metres is the width of a Turin square's corner.
    static let arrivalRadius = 20

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

    /// The straight-line distance now, from the live fix rather than from when
    /// the screen opened.
    private var currentDistance: Int {
        model.fountains.first { $0.id == fountain.id }?.distance ?? fountain.distance
    }

    private var hasArrived: Bool { currentDistance <= Self.arrivalRadius }

    /// MapKit had nothing to say about streets: no network, or nowhere to walk.
    private var isStraightLine: Bool { hasAnswered && route.polyline == nil }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $camera) {
                UserAnnotation { UserMark() }

                if let polyline = route.polyline {
                    // Stock under black ink, so the line prints cleanly over any street.
                    MapPolyline(polyline)
                        .stroke(Palette.carta, style: StrokeStyle(lineWidth: 12, lineCap: .butt, lineJoin: .miter))
                    MapPolyline(polyline)
                        .stroke(Palette.inchiostro, style: StrokeStyle(lineWidth: 6, lineCap: .butt, lineJoin: .miter))
                } else if isStraightLine {
                    MapPolyline(coordinates: [model.origin, fountain.coordinate])
                        .stroke(
                            Palette.inchiostro,
                            style: StrokeStyle(lineWidth: 4, lineCap: .butt, dash: [9, 7])
                        )
                }

                Annotation(fountain.place, coordinate: fountain.coordinate, anchor: .center) {
                    FountainPin(
                        fountain: fountain, isSelected: true,
                        density: .full, token: model.selectionToken
                    ) {}
                }
                .annotationTitles(.hidden)
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControlVisibility(.hidden)
            .colorMultiply(Palette.mapWash)
            .ignoresSafeArea()

            VStack(spacing: 10) {
                instruction
                Spacer()
                if isStraightLine && !hasArrived { straightLineNote }
                progress
                closeButton
            }
            .padding(.horizontal, 12)
            .padding(.top, Screen.safeArea.top + 8)
            .padding(.bottom, Screen.safeArea.bottom + 4)
        }
        .ignoresSafeArea()
        .sensoryFeedback(.success, trigger: hasArrived) { _, arrived in arrived }
        .task {
            // The same walk, on the Lock Screen and in the Dynamic Island.
            WalkActivityController.shared.begin(to: fountain, from: model.origin)
            await recompute(reframing: true)
        }
        .onDisappear { WalkActivityController.shared.end() }
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
        withAnimation(reduceMotion ? nil : Motion.ui) {
            route = walked
            hasAnswered = true
            if reframing {
                camera = .rect(Self.framing(walked.polyline?.boundingMapRect, from: from, to: fountain.coordinate))
            }
        }
        routedFrom = from
        // Without MapKit's answer the route is only the straight line, which the
        // controller already measures better than a stale figure.
        WalkActivityController.shared.routeDidChange(
            remaining: walked.polyline == nil ? nil : walked.remaining,
            toNextTurn: walked.toNextTurn, instruction: walked.headline,
            routedFrom: from
        )
    }

    /// The whole walk, with room round it for the two plates that cover the top
    /// and the foot of the screen — the walk should sit in the strip between them.
    static func framing(
        _ rect: MKMapRect?, from origin: CLLocationCoordinate2D, to target: CLLocationCoordinate2D
    ) -> MKMapRect {
        let base = rect ?? {
            let a = MKMapPoint(origin), b = MKMapPoint(target)
            return MKMapRect(
                x: min(a.x, b.x), y: min(a.y, b.y),
                width: abs(a.x - b.x), height: abs(a.y - b.y)
            )
        }()
        // About 160 m at Turin's latitude is the least worth showing.
        let floor = 160 * MKMapPointsPerMeterAtLatitude(origin.latitude)
        let width = max(base.width, floor), height = max(base.height, floor)
        let centred = MKMapRect(
            x: base.midX - width / 2, y: base.midY - height / 2, width: width, height: height
        )
        return centred.insetBy(dx: -width * 0.45, dy: -height * 1.05)
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
        let nextIsTurn = route.steps.first?.kind != .arrive
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                if hasArrived {
                    Text("Chegou")
                        .font(Typo.display(min(figureSize * 0.62, 96), 900))
                        .foregroundStyle(Palette.carta)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("A fonte está aqui.")
                        .font(Typo.ui(22, 700))
                        .foregroundStyle(Palette.carta)
                        .padding(.top, 6)
                    Text(fountain.place)
                        .font(Typo.ui(15))
                        .foregroundStyle(Palette.carta.opacity(0.8))
                        .padding(.top, 4)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        CountingMetres(
                            metres: route.toNextTurn, token: route.remaining,
                            size: min(figureSize, 150), weight: 900, color: Palette.carta,
                            tracking: Typo.tracking(-0.03, at: 120)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        Text("m")
                            .font(Typo.ui(24, 700))
                            .foregroundStyle(Palette.carta.opacity(0.85))
                    }
                    Text(isStraightLine ? String(localized: "Siga na direção da fonte") : route.headline)
                        .font(Typo.ui(22, 700))
                        .foregroundStyle(Palette.carta)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                    Text(subhead)
                        .font(Typo.ui(15))
                        .foregroundStyle(Palette.carta.opacity(0.8))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
            // The sun, with what to do on it: a turn, or the arrival.
            ZStack {
                Circle().fill(Palette.sole)
                if hasArrived {
                    StateMark(state: fountain.state, size: 26)
                } else if nextIsTurn {
                    IconView(shape: Icon.TurnRight(), size: 26, weight: 3, tint: Palette.inchiostro)
                } else {
                    Circle().fill(Palette.inchiostro).frame(width: 14, height: 14)
                }
            }
            .frame(width: 58, height: 58)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.inchiostro)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityLabel(
            hasArrived
                ? String(localized: "Você chegou à fonte, \(fountain.place)")
                : String(localized: "\(route.toNextTurn) metros. \(route.headline). \(subhead)")
        )
    }

    /// The line under the headline: what comes after, or, with no streets to go
    /// by, which way to face.
    private var subhead: String {
        if isStraightLine {
            return Landmark.orientation(for: fountain.bearing, from: model.origin)
        }
        return route.subhead
    }

    /// The honest line for the day there is no route: the app is guessing a
    /// direction, not reading a street plan, and says so.
    private var straightLineNote: some View {
        HStack(spacing: 12) {
            EmptySceneMini(kind: .noStreetRoute, height: 52)
            Text("Sem rota de ruas: siga na direção da fonte.")
                .font(Typo.ui(14, 600))
                .foregroundStyle(Palette.inchiostro)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .plate(border: Palette.rosso)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }

    // MARK: Where you are in the walk

    private var progress: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                figures(stacked: false)
                figures(stacked: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            let upcoming = Array(route.steps.dropFirst())
            if !upcoming.isEmpty && !hasArrived {
                PosterRule()
                VStack(spacing: 0) {
                    ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, step in
                        HStack(spacing: 12) {
                            ZStack {
                                switch step.kind {
                                case .turn:
                                    IconView(
                                        shape: Icon.TurnRight(), size: 15,
                                        weight: 2.2, tint: Palette.inchiostro
                                    )
                                case .arrive:
                                    Circle().fill(Palette.blu).frame(width: 12, height: 12)
                                }
                            }
                            .frame(width: 24, height: 24)

                            Text(step.instruction)
                                .font(Typo.ui(14.5, 600))
                                .foregroundStyle(Palette.inchiostro)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if step.distance > 0 {
                                Text("\(step.distance) m")
                                    .font(Typo.ui(13.5, 600))
                                    .foregroundStyle(Palette.ink(0.75))
                            }
                        }
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            if index < upcoming.count - 1 { PosterRule(weight: .light) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .plate()
        .animation(reduceMotion ? nil : Motion.ui, value: route.steps.count)
    }

    /// Minutes and metres left, as two heavy figures split by a rule.
    @ViewBuilder
    private func figures(stacked: Bool) -> some View {
        let minutes = figure(value: hasArrived ? "0" : "\(route.minutes)", unit: "min", caption: String(localized: "Chegada às \(route.arrival())"))
        let remaining = figure(value: "\(hasArrived ? 0 : route.remaining)", unit: "m", caption: String(localized: "restantes"))
        if stacked {
            VStack(alignment: .leading, spacing: 10) { minutes; remaining }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 0) {
                minutes.frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Palette.inchiostro).frame(width: 3, height: 58)
                remaining.padding(.leading, 18).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func figure(value: String, unit: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(Typo.display(44, 900))
                    .foregroundStyle(Palette.inchiostro)
                    .monospacedDigit()
                Text(unit)
                    .font(Typo.ui(16, 700))
                    .foregroundStyle(Palette.inchiostro)
            }
            Text(caption)
                .font(Typo.ui(13, 500))
                .foregroundStyle(Palette.ink(0.75))
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var closeButton: some View {
        if hasArrived {
            PosterActionButton(title: String(localized: "Concluir"), height: 52) { dismiss() }
        } else {
            PosterOutlineButton(title: String(localized: "Encerrar rota"), height: 50) { dismiss() }
                .background(Palette.carta)
        }
    }
}
