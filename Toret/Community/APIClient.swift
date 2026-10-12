import Foundation

/// Where the Toret API lives, and whether this build talks to it at all.
enum APIConfiguration {
    /// The one place the address is written. Every route is under `/v1`.
    static let defaultBaseURL = URL(string: "https://torino.deepdive.dev.br")!

    /// The address given with `-toret-api <url>`, if it is a usable one.
    static func launchOverride(in arguments: [String]) -> URL? {
        guard let flag = arguments.firstIndex(of: "-toret-api"), arguments.indices.contains(flag + 1),
              let url = URL(string: arguments[flag + 1]),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false
        else { return nil }
        return url
    }

    /// The server this build talks to, or nil when it stays on the device.
    ///
    /// A Release build always uses the constant. A Debug build keeps reports on
    /// the device unless `-toret-api` names a server, so running from Xcode never
    /// writes to the real one by accident.
    static func resolvedBaseURL(arguments: [String] = ProcessInfo.processInfo.arguments) -> URL? {
        #if DEBUG
        return launchOverride(in: arguments)
        #else
        return defaultBaseURL
        #endif
    }
}

/// One HTTP exchange with the Toret API: the base address, the headers every
/// request carries, a cache of ETags and the server's requests to slow down.
///
/// Everything is `async` and runs off the main actor, and a request that cannot
/// get through fails within ten seconds, so no screen ever waits on the network.
/// What comes back is either a response worth reading or a ``CommunityError``:
///
/// - a network failure, a timeout, a `408` or a `5xx` is `.unavailable`;
/// - a `429`, or a `503` with `Retry-After`, is `.retryLater`, and until that time
///   has passed the client does not call the network at all;
/// - every other status is returned, because for a write a refusal is an answer.
actor APIClient {
    /// Reads and writes are throttled separately: being told to slow down on
    /// writes must not stop the feed from loading.
    private enum Lane: Hashable { case read, write }

    struct Response: Sendable {
        let status: Int
        let data: Data
    }

    /// How long a `429` with no `Retry-After` is honoured.
    static let defaultRetryAfter = 60
    /// No server can park the client for longer than this.
    private static let longestRetryAfter = 3600
    private static let etagLimit = 40

    let baseURL: URL
    private let session: URLSession
    private let clock: @Sendable () -> Date
    private let clientHeader: String
    private var etags: [URL: (etag: String, body: Data)] = [:]
    private var etagOrder: [URL] = []
    private var holds: [Lane: (until: Date, rateLimited: Bool)] = [:]
    private var lastSuccess: Date?
    /// Whether the latest call got an answer.
    private var lastCallSucceeded = false

    init(
        baseURL: URL,
        session: URLSession = APIClient.makeSession(),
        clientHeader: String = APIClient.clientVersion(),
        clock: @escaping @Sendable () -> Date = { .now }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.clientHeader = clientHeader
        self.clock = clock
    }

    /// No cache of its own (the ETags are kept by hand, below), no waiting for a
    /// connection that is not there, and ten seconds for anything.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    /// "1.0.0+42", for the server's logs.
    static func clientVersion(from info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version)+\(build)"
    }

    /// Whether the latest call reached the server, and did so a moment ago.
    func reachedServer(within seconds: TimeInterval) -> Bool {
        guard lastCallSucceeded, let lastSuccess else { return false }
        return clock().timeIntervalSince(lastSuccess) < seconds
    }

    /// Sends one request. A `GET` is conditional on the ETag of the last answer
    /// for the same address, and a `304` comes back as that answer's `200`.
    func send(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> Response {
        let lane: Lane = method == "GET" ? .read : .write
        let now = clock()
        if let hold = holds[lane] {
            if hold.until > now {
                throw CommunityError.retryLater(
                    seconds: Int(hold.until.timeIntervalSince(now).rounded(.up)), rateLimited: hold.rateLimited
                )
            }
            holds[lane] = nil
        }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw CommunityError.unavailable
        }
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw CommunityError.unavailable }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(clientHeader, forHTTPHeaderField: "X-Toret-Client")
        if let body {
            request.httpBody = body
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if method == "GET", let cached = etags[url] {
            request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            lastCallSucceeded = false
            throw CommunityError.unavailable
        }
        guard let http = response as? HTTPURLResponse else {
            lastCallSucceeded = false
            throw CommunityError.unavailable
        }

        switch http.statusCode {
        case 304:
            guard let cached = etags[url] else { throw CommunityError.unavailable }
            lastSuccess = clock()
            lastCallSucceeded = true
            return Response(status: 200, data: cached.body)
        case 429:
            let seconds = Self.retryAfter(http) ?? Self.defaultRetryAfter
            holds[lane] = (clock().addingTimeInterval(TimeInterval(seconds)), true)
            throw CommunityError.retryLater(seconds: seconds, rateLimited: true)
        case 503:
            guard let seconds = Self.retryAfter(http) else { throw CommunityError.unavailable }
            holds[lane] = (clock().addingTimeInterval(TimeInterval(seconds)), false)
            throw CommunityError.retryLater(seconds: seconds, rateLimited: false)
        case 408, 500...:
            lastCallSucceeded = false
            throw CommunityError.unavailable
        default:
            lastSuccess = clock()
            lastCallSucceeded = true
            if method == "GET", http.statusCode == 200, let etag = http.value(forHTTPHeaderField: "ETag") {
                remember(etag: etag, body: data, for: url)
            }
            return Response(status: http.statusCode, data: data)
        }
    }

    /// `Retry-After` in seconds, at least 1 and at most an hour. The HTTP-date
    /// form is not used by this API and counts as absent.
    private static func retryAfter(_ response: HTTPURLResponse) -> Int? {
        guard let text = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = Int(text.trimmingCharacters(in: .whitespaces))
        else { return nil }
        return min(longestRetryAfter, max(1, seconds))
    }

    private func remember(etag: String, body: Data, for url: URL) {
        if etags[url] == nil {
            etagOrder.append(url)
            if etagOrder.count > Self.etagLimit { etags[etagOrder.removeFirst()] = nil }
        }
        etags[url] = (etag, body)
    }
}
