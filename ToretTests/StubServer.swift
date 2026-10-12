import CryptoKit
import Foundation

@testable import Toret

/// One request that reached the stub.
struct RecordedRequest: Sendable {
    let method: String
    let url: URL
    let headers: [String: String]
    let body: Data

    var path: String { url.path }

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    var query: [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.compactMap { item in item.value.map { (item.name, $0) } }, uniquingKeysWith: { first, _ in first })
    }
}

enum StubReply: Sendable {
    case reply(status: Int, headers: [String: String] = [:], body: Data = Data())
    case fail(URLError.Code)

    static func json(_ status: Int, _ text: String, headers: [String: String] = [:]) -> StubReply {
        .reply(status: status, headers: headers.merging(["Content-Type": "application/json"]) { first, _ in first }, body: Data(text.utf8))
    }
}

/// A fake server for `URLSession`: every test gets a host of its own, so tests that
/// run in parallel never see each other's requests.
final class StubServer: @unchecked Sendable {
    let host = "stub-\(UUID().uuidString.lowercased()).test"
    var baseURL: URL { URL(string: "https://\(host)")! }

    private let lock = NSLock()
    private var handler: @Sendable (RecordedRequest) -> StubReply
    private var log: [RecordedRequest] = []

    init(_ handler: @escaping @Sendable (RecordedRequest) -> StubReply = { _ in .fail(.cannotConnectToHost) }) {
        self.handler = handler
        StubRegistry.shared.add(self)
    }

    deinit { StubRegistry.shared.remove(host) }

    func respond(_ handler: @escaping @Sendable (RecordedRequest) -> StubReply) {
        lock.withLock { self.handler = handler }
    }

    var requests: [RecordedRequest] { lock.withLock { log } }

    var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        configuration.timeoutIntervalForRequest = 10
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    func client(clock: @escaping @Sendable () -> Date = { .now }) -> APIClient {
        APIClient(baseURL: baseURL, session: session, clientHeader: "1.0.0+7", clock: clock)
    }

    fileprivate func handle(_ request: RecordedRequest) -> StubReply {
        let current = lock.withLock {
            log.append(request)
            return handler
        }
        return current(request)
    }
}

private final class StubRegistry: @unchecked Sendable {
    static let shared = StubRegistry()
    private let lock = NSLock()
    private var servers: [String: Weak] = [:]

    private struct Weak { weak var server: StubServer? }

    func add(_ server: StubServer) { lock.withLock { servers[server.host] = Weak(server: server) } }
    func remove(_ host: String) { lock.withLock { servers[host] = nil } }
    func server(for host: String?) -> StubServer? {
        guard let host else { return nil }
        return lock.withLock { servers[host]?.server }
    }
}

final class StubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        StubRegistry.shared.server(for: request.url?.host) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let server = StubRegistry.shared.server(for: url.host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        // URLSession turns a request body into a stream before a protocol sees it.
        let recorded = RecordedRequest(
            method: request.httpMethod ?? "GET", url: url,
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody ?? Self.read(request.httpBodyStream)
        )
        switch server.handle(recorded) {
        case let .fail(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case let .reply(status, headers, body):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

// MARK: - A small copy of the v1 server

/// The routes of docs/backend/api.md that the app uses, enough to run the
/// community store against `HTTPBackend` end to end. It derives the handle from the
/// install header the way the real server does.
final class FakeAPI: @unchecked Sendable {
    struct Stored {
        var report: Report
        let install: String
        var lagging: Bool
        var deleted = false
    }

    private let lock = NSLock()
    private var stored: [String: Stored] = [:]
    private var flagged: [(id: String, reason: String, install: String)] = []
    private var down = false
    private var lag = false

    let server = StubServer()

    init() {
        server.respond { [unowned self] in self.route($0) }
    }

    /// While true every request fails as if there were no network.
    func setOffline(_ offline: Bool) { lock.withLock { down = offline } }

    /// While true a new or deleted report takes a moment to show up in lists, as the
    /// real indexes do: a new one is missing from them, a deleted one is still there.
    func setLag(_ value: Bool) { lock.withLock { lag = value } }

    /// The indexes catch up.
    func settle() {
        lock.withLock {
            for id in stored.keys { stored[id]?.lagging = false }
            stored = stored.filter { !$0.value.deleted }
        }
    }

    var reports: [Report] { lock.withLock { stored.values.filter { !$0.deleted }.map(\.report) } }
    var flags: [(id: String, reason: String, install: String)] { lock.withLock { flagged } }

    func seed(_ report: Report, install: String = "other-install-0000") {
        lock.withLock { stored[report.id] = Stored(report: report, install: install, lagging: false) }
    }

    private func route(_ request: RecordedRequest) -> StubReply {
        if lock.withLock({ down }) { return .fail(.notConnectedToInternet) }
        let parts = request.path.split(separator: "/").map(String.init)
        guard parts.first == "v1" else { return .json(404, #"{"message":"Not Found"}"#) }
        switch (request.method, parts.count) {
        case ("GET", 2) where parts[1] == "health":
            return .json(200, #"{"status":"ok","version":"test","catalogue":723}"#)
        case ("GET", 2) where parts[1] == "reports":
            return list(request, fountain: nil)
        case ("GET", 4) where parts[1] == "fountains" && parts[3] == "reports":
            return list(request, fountain: parts[2])
        case ("POST", 2) where parts[1] == "reports":
            return create(request)
        case ("DELETE", 3) where parts[1] == "reports":
            return remove(request, id: parts[2])
        case ("POST", 4) where parts[1] == "reports" && parts[3] == "flag":
            return flag(request, id: parts[2])
        default:
            return .json(404, #"{"message":"Not Found"}"#)
        }
    }

    private func list(_ request: RecordedRequest, fountain: String?) -> StubReply {
        let limit = Int(request.query["limit"] ?? "") ?? 50
        let visible = lock.withLock {
            stored.values.filter { entry in
                let shown = entry.deleted ? lag : !entry.lagging
                return shown && (fountain == nil || entry.report.fountainID == fountain)
            }
        }
        .map(\.report).sorted { $0.date > $1.date }.prefix(limit)
        guard let data = try? FilePersistence.encoder.encode(["reports": Array(visible)]) else {
            return .json(500, "{}")
        }
        return .reply(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    private struct Incoming: Decodable {
        let id: String
        let fountainID: String
        let state: WaterState
        let rating: Int?
        let tags: [ReportTag]?
        let note: String?
        let date: Date
    }

    private func create(_ request: RecordedRequest) -> StubReply {
        guard let install = request.header("X-Toret-Install"), InstallToken.isValid(install) else {
            return .json(401, #"{"error":{"code":"install_required","message":""}}"#)
        }
        guard let incoming = try? FilePersistence.decoder.decode(Incoming.self, from: request.body) else {
            return .json(400, #"{"error":{"code":"bad_request","message":""}}"#)
        }
        if incoming.state == .unknown, incoming.rating == nil {
            return .json(422, #"{"error":{"code":"empty_report","message":"","field":"state"}}"#)
        }
        let id = incoming.id.uppercased()
        return lock.withLock {
            if let existing = stored[id] {
                return existing.install == install ? reply(existing.report, status: 200) : .json(409, #"{"error":{"code":"id_conflict","message":""}}"#)
            }
            let report = Report(
                id: id, fountainID: incoming.fountainID, state: incoming.state, rating: incoming.rating,
                tags: incoming.tags ?? [], note: incoming.note ?? "", date: incoming.date,
                author: AuthorHandle.make(from: install), isMine: false
            )
            stored[id] = Stored(report: report, install: install, lagging: lag)
            return reply(report, status: 201)
        }
    }

    private func reply(_ report: Report, status: Int) -> StubReply {
        guard let data = try? FilePersistence.encoder.encode(report) else { return .json(500, "{}") }
        return .reply(status: status, headers: ["Content-Type": "application/json"], body: data)
    }

    private func remove(_ request: RecordedRequest, id: String) -> StubReply {
        guard let install = request.header("X-Toret-Install") else {
            return .json(401, #"{"error":{"code":"install_required","message":""}}"#)
        }
        return lock.withLock {
            guard let existing = stored[id.uppercased()] else { return .reply(status: 204) }
            guard existing.install == install else { return .json(403, #"{"error":{"code":"not_owner","message":""}}"#) }
            stored[id.uppercased()]?.deleted = true
            if !lag { stored[id.uppercased()] = nil }
            return .reply(status: 204)
        }
    }

    private func flag(_ request: RecordedRequest, id: String) -> StubReply {
        let install = request.header("X-Toret-Install") ?? ""
        let reason = (try? JSONSerialization.jsonObject(with: request.body) as? [String: String])?["reason"] ?? ""
        lock.withLock { flagged.append((id, reason, install)) }
        return .reply(status: 204)
    }
}

/// Polls until the condition holds or the time runs out, for work that happens on
/// tasks the test does not own.
@MainActor
func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

/// A report as the stub server would list it.
func serverReport(
    _ id: String, fountain: String = "f1", state: WaterState = .running,
    author: String = "Visitante AAAAAA", at date: Date = Date(timeIntervalSince1970: 1_800_000_000)
) -> Report {
    Report(id: id, fountainID: fountain, state: state, date: date, author: author, isMine: false)
}
