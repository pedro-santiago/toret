import Foundation

/// Where a `toret://` URL goes.
///
/// Widgets, controls, Siri and notifications all end the same way: the app opens
/// on one specific thing. One small grammar, parsed in one place, so a widget row
/// and a shortcut cannot disagree about what "open this fountain" means.
///
///     toret://compass              the compass, on whatever is selected
///     toret://compass/nearest      the compass, on the nearest fountain
///     toret://fountain/<id>        one fountain's page
///     toret://route/<id>           walking to that fountain
///     toret://route/nearest        walking to the nearest one
enum DeepLink: Equatable, Sendable {
    case compass(nearest: Bool)
    case fountain(String)
    case route(String)
    case routeToNearest

    static let scheme = "toret"
    private static let nearestToken = "nearest"

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host?.lowercased() else {
            return nil
        }
        let argument = url.pathComponents.dropFirst().first.flatMap { $0.isEmpty ? nil : $0 }
        switch host {
        case "compass":
            switch argument {
            case nil: self = .compass(nearest: false)
            case Self.nearestToken?: self = .compass(nearest: true)
            default: return nil
            }
        case "fountain":
            guard let argument else { return nil }
            self = .fountain(argument)
        case "route":
            guard let argument else { return nil }
            self = argument == Self.nearestToken ? .routeToNearest : .route(argument)
        default:
            return nil
        }
    }

    var url: URL {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        switch self {
        case let .compass(nearest):
            parts.host = "compass"
            if nearest { parts.path = "/\(Self.nearestToken)" }
        case let .fountain(id):
            parts.host = "fountain"
            parts.path = "/\(id)"
        case let .route(id):
            parts.host = "route"
            parts.path = "/\(id)"
        case .routeToNearest:
            parts.host = "route"
            parts.path = "/\(Self.nearestToken)"
        }
        // The pieces above are all ASCII tokens or OpenStreetMap node ids.
        return parts.url ?? URL(string: "\(Self.scheme)://compass")!
    }
}
