import CoreLocation
import Foundation
import MapKit

/// A walk to a fountain, in the only two pieces that matter while you are moving:
/// what to do next, and what to do after that.
///
/// Not `Sendable`: it carries an `MKPolyline`, a reference type owned by MapKit.
/// The route is built and read on the main actor, which is where the map that
/// draws it lives anyway.
@MainActor
struct WalkingRoute: Hashable {
    struct Step: Hashable, Identifiable, Sendable {
        enum Kind: Hashable, Sendable { case turn, arrive }

        let instruction: String
        let distance: Int
        let kind: Kind

        var id: String { "\(instruction)-\(distance)" }
    }

    let destination: Fountain
    let steps: [Step]
    /// Metres left on the whole walk.
    let remaining: Int
    /// Metres to the next instruction — the figure set large at the top.
    let toNextTurn: Int
    let headline: String
    let subhead: String
    let minutes: Int
    /// The line drawn on the map. Empty until MapKit answers.
    let polyline: MKPolyline?

    /// The straight-line fallback, used before MapKit answers and if it never does.
    ///
    /// It is honest about what it is: no street names, just the distance and the
    /// direction, which is still enough to start walking on.
    init(to fountain: Fountain) {
        destination = fountain
        let total = fountain.distance
        let firstLeg = max(10, Int((Double(total) * 0.75 / 10).rounded()) * 10)
        let lastLeg = max(10, total - firstLeg)

        steps = [
            Step(instruction: String(localized: "Siga na direção da fonte"), distance: firstLeg, kind: .turn),
            Step(instruction: String(localized: "Chegada à fonte"), distance: lastLeg, kind: .arrive),
        ]
        remaining = total
        toNextTurn = firstLeg
        headline = String(localized: "Siga na direção da fonte")
        subhead = String(localized: "\(fountain.place), a \(DistanceFormat.short(total))")
        minutes = fountain.walkingMinutes
        polyline = nil
    }

    /// The real thing, from MapKit's walking directions.
    init(to fountain: Fountain, route: MKRoute) {
        destination = fountain

        // MapKit's first step is always "Proceed to <street>", which is a
        // restatement of "you are here" — drop it and start on the first turn.
        let usable = route.steps.filter { !$0.instructions.isEmpty }.dropFirst()
        // MapKit's last step is the arrival; mark it rather than adding another.
        var built = usable.enumerated().map { index, step in
            Step(
                instruction: index == usable.count - 1 ? String(localized: "Chegada à fonte") : step.instructions,
                distance: Int(step.distance.rounded()),
                kind: index == usable.count - 1 ? .arrive : .turn
            )
        }
        if built.isEmpty {
            built = [Step(instruction: String(localized: "Chegada à fonte"), distance: 0, kind: .arrive)]
        }
        steps = Array(built.prefix(4))

        remaining = Int(route.distance.rounded())
        toNextTurn = built.first.map(\.distance) ?? remaining
        headline = built.first?.instruction ?? String(localized: "Siga em frente")
        subhead = built.dropFirst().first.map { String(localized: "Depois: \($0.instruction)") }
            ?? fountain.place
        minutes = max(1, Int((route.expectedTravelTime / 60).rounded()))
        polyline = route.polyline
    }

    /// Clock time you get there.
    func arrival(from now: Date = .now) -> String {
        Formatting.clock(now.addingTimeInterval(Double(minutes) * 60))
    }

    /// Asks MapKit to walk it properly.
    static func directions(
        from origin: CLLocationCoordinate2D, to fountain: Fountain
    ) async -> WalkingRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(
            location: CLLocation(latitude: origin.latitude, longitude: origin.longitude),
            address: nil
        )
        request.destination = MKMapItem(
            location: CLLocation(
                latitude: fountain.latitude, longitude: fountain.longitude
            ),
            address: nil
        )
        request.transportType = .walking

        guard let response = try? await MKDirections(request: request).calculate(),
              let route = response.routes.first
        else {
            // No network, or nowhere to walk: the straight line still gets you there.
            return WalkingRoute(to: fountain)
        }
        return WalkingRoute(to: fountain, route: route)
    }
}
