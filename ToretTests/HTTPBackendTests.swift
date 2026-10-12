import CryptoKit
import Foundation
import Testing

@testable import Toret

private let token = "5B0C6E0D-7F7B-4D5E-9E3A-2C1F8A4B9D10"

private func makeBackend(
    _ server: StubServer, clock: TestClock = TestClock()
) -> HTTPBackend {
    HTTPBackend(client: server.client(clock: { clock.now }), installToken: { token })
}

private func list(_ reports: [Report]) -> StubReply {
    let data = (try? FilePersistence.encoder.encode(["reports": reports])) ?? Data()
    return .reply(status: 200, headers: ["Content-Type": "application/json", "ETag": "\"abc123\""], body: data)
}

@Suite("HTTP backend")
struct HTTPBackendTests {
    @Test("A list is read, newest first as sent, with the client header and no install token")
    func reading() async throws {
        let server = StubServer { _ in list([serverReport("A"), serverReport("B", fountain: "f2")]) }
        let reports = try await makeBackend(server).recent(limit: 200)
        #expect(reports.map(\.id) == ["A", "B"])
        #expect(reports.allSatisfy { !$0.isMine })

        let sent = try #require(server.requests.first)
        #expect(sent.method == "GET")
        #expect(sent.path == "/v1/reports")
        #expect(sent.query["limit"] == "200")
        #expect(sent.header("X-Toret-Client") == "1.0.0+7")
        #expect(sent.header("X-Toret-Install") == nil)
    }

    @Test("One fountain's list uses its own route")
    func fountainRoute() async throws {
        let server = StubServer { _ in list([]) }
        _ = try await makeBackend(server).reports(for: "421310659", limit: 40)
        #expect(server.requests.first?.path == "/v1/fountains/421310659/reports")
        #expect(server.requests.first?.query["limit"] == "40")
    }

    @Test("A record this app cannot read is skipped, the rest of the list is kept")
    func lossy() async throws {
        let text = """
        {"reports":[
          {"id":"A","fountainID":"f1","state":"running","tags":["cold","from-the-future"],"note":"ok","date":"2026-10-12T09:41:00Z","author":"Visitante E95596","isMine":false},
          {"id":"B","fountainID":"f1","state":"gushing","tags":[],"note":"","date":"2026-10-12T09:41:00Z","author":"Visitante AAAAAA","isMine":false},
          {"id":"C","fountainID":"f1","state":"weak","rating":9,"tags":[],"note":"","date":"2026-10-12T09:41:00Z","author":"Visitante AAAAAA","isMine":false}
        ],"somethingNew":1}
        """
        let server = StubServer { _ in .json(200, text) }
        let reports = try await makeBackend(server).recent(limit: 50)
        #expect(reports.map(\.id) == ["A", "C"])
        #expect(reports[0].tags == [.cold])
        #expect(reports[1].rating == 5, "the rating is clamped like any other")
    }

    @Test("Malformed JSON, an HTML page or an unknown route is a failure, never an empty list")
    func malformed() async {
        for reply in [
            StubReply.json(200, "{not json"),
            .json(200, #"{"reports":"none"}"#),
            .reply(status: 200, body: Data("<html>captive portal</html>".utf8)),
            .json(404, #"{"message":"Not Found"}"#),
            .json(404, #"{"error":{"code":"unknown_fountain","message":""}}"#),
            .json(500, #"{"error":{"code":"internal","message":""}}"#),
        ] {
            let server = StubServer { _ in reply }
            await #expect(throws: CommunityError.unavailable) {
                try await makeBackend(server).reports(for: "f1", limit: 40)
            }
        }
    }

    @Test("Offline, reads and writes fail as unavailable and the server reads as unavailable")
    func offline() async throws {
        let server = StubServer { _ in .fail(.notConnectedToInternet) }
        let backend = makeBackend(server)
        await #expect(throws: CommunityError.unavailable) { try await backend.recent(limit: 50) }
        await #expect(throws: CommunityError.unavailable) { try await backend.save(serverReport("A")) }
        #expect(await backend.availability() == .unavailable)
    }

    @Test("A timeout is retried later like any network failure")
    func timeout() async {
        let server = StubServer { _ in .fail(.timedOut) }
        await #expect(throws: CommunityError.unavailable) { try await makeBackend(server).delete(reportID: "A") }
    }

    // MARK: Caching

    @Test("A 304 returns the list from the last 200 and the ETag is sent back")
    func notModified() async throws {
        let server = StubServer { request in
            request.header("If-None-Match") == "\"abc123\""
                ? .reply(status: 304, headers: ["ETag": "\"abc123\""])
                : list([serverReport("A")])
        }
        let backend = makeBackend(server)
        #expect(try await backend.recent(limit: 50).map(\.id) == ["A"])
        #expect(try await backend.recent(limit: 50).map(\.id) == ["A"])
        let sent = server.requests
        #expect(sent.count == 2)
        #expect(sent[0].header("If-None-Match") == nil)
        #expect(sent[1].header("If-None-Match") == "\"abc123\"")
    }

    @Test("Each address has its own ETag")
    func etagPerAddress() async throws {
        let server = StubServer { request in
            request.path.contains("/fountains/")
                ? .reply(status: 200, headers: ["ETag": "\"fountain\""], body: Data(#"{"reports":[]}"#.utf8))
                : list([serverReport("A")])
        }
        let backend = makeBackend(server)
        _ = try await backend.recent(limit: 50)
        _ = try await backend.reports(for: "f1", limit: 40)
        #expect(server.requests[1].header("If-None-Match") == nil)
    }

    @Test("A 304 with nothing cached is a failure, not an empty list")
    func strayNotModified() async {
        let server = StubServer { _ in .reply(status: 304) }
        await #expect(throws: CommunityError.unavailable) { try await makeBackend(server).recent(limit: 50) }
    }

    // MARK: Writing

    @Test("A save posts the report with the install token and without an author")
    func saving() async throws {
        let server = StubServer { _ in .json(201, "{}") }
        let report = Report(
            id: "7D2B7C54-3F0A-4C5E-8B6D-0E5C6C1B9A10", fountainID: "421310659", state: .running,
            rating: 5, tags: [.cold, .clean], note: "Água gelada, sem fila.",
            date: Date(timeIntervalSince1970: 1_791_798_060), author: "Visitante 123456"
        )
        try await makeBackend(server).save(report)

        let sent = try #require(server.requests.first)
        #expect(sent.method == "POST")
        #expect(sent.path == "/v1/reports")
        #expect(sent.header("X-Toret-Install") == token)
        #expect(sent.header("Content-Type")?.hasPrefix("application/json") == true)
        let body = try #require(try JSONSerialization.jsonObject(with: sent.body) as? [String: Any])
        #expect(body["id"] as? String == report.id)
        #expect(body["fountainID"] as? String == "421310659")
        #expect(body["state"] as? String == "running")
        #expect(body["rating"] as? Int == 5)
        #expect(body["tags"] as? [String] == ["cold", "clean"])
        #expect(body["note"] as? String == "Água gelada, sem fila.")
        #expect(body["date"] as? String == "2026-10-12T09:41:00Z")
        #expect(body["author"] == nil)
        #expect(body["isMine"] == nil)
    }

    @Test("Saving the same report again, after a failed try, lands once")
    func idempotentRetry() async throws {
        let api = FakeAPI()
        let backend = makeBackend(api.server)
        let report = Report(fountainID: "f1", state: .running, rating: 4, author: "Visitante 111111")

        api.setOffline(true)
        await #expect(throws: CommunityError.unavailable) { try await backend.save(report) }
        #expect(api.reports.isEmpty)

        api.setOffline(false)
        try await backend.save(report)
        try await backend.save(report)
        try await backend.save(report)
        #expect(api.reports.count == 1)
        #expect(api.reports.first?.author == AuthorHandle.make(from: token))
    }

    @Test("A 429 with Retry-After is a wait: nothing more is sent until it has passed")
    func rateLimited() async throws {
        let clock = TestClock()
        let server = StubServer { _ in
            .json(429, #"{"error":{"code":"rate_limited","message":"","reason":"fountain"}}"#, headers: ["Retry-After": "150"])
        }
        let backend = makeBackend(server, clock: clock)
        let expected = CommunityError.rejected(.rateLimited(minutesLeft: 3))

        await #expect(throws: expected) { try await backend.save(serverReport("A")) }
        #expect(server.requests.count == 1)

        // Still inside the wait: refused without a request, deletes and flags too.
        clock.advance(100)
        await #expect(throws: CommunityError.rejected(.rateLimited(minutesLeft: 1))) { try await backend.save(serverReport("B")) }
        await #expect(throws: (any Error).self) { try await backend.delete(reportID: "A") }
        #expect(server.requests.count == 1)

        clock.advance(60)
        await #expect(throws: expected) { try await backend.save(serverReport("A")) }
        #expect(server.requests.count == 2)
    }

    @Test("Being told to wait on writes does not stop reads")
    func readsKeepGoing() async throws {
        let server = StubServer { request in
            request.method == "GET" ? list([serverReport("A")]) : .json(429, "{}", headers: ["Retry-After": "600"])
        }
        let backend = makeBackend(server)
        await #expect(throws: (any Error).self) { try await backend.save(serverReport("A")) }
        #expect(try await backend.recent(limit: 50).count == 1)
    }

    @Test("A 429 without Retry-After waits a minute")
    func rateLimitedWithoutHeader() async {
        let server = StubServer { _ in .json(429, #"{"message":"Too Many Requests"}"#) }
        await #expect(throws: CommunityError.rejected(.rateLimited(minutesLeft: 1))) {
            try await makeBackend(server).save(serverReport("A"))
        }
    }

    @Test("A 503 stays queued; a 5xx is unavailable")
    func serverTrouble() async {
        let busy = StubServer { _ in .json(503, "{}", headers: ["Retry-After": "30"]) }
        await #expect(throws: CommunityError.retryLater(seconds: 30, rateLimited: false)) {
            try await makeBackend(busy).delete(reportID: "A")
        }
        let broken = StubServer { _ in .json(500, "{}") }
        await #expect(throws: CommunityError.unavailable) { try await makeBackend(broken).save(serverReport("A")) }
    }

    @Test("Permanent refusals are surfaced when the sheet has words for them, and dropped otherwise")
    func permanent() async throws {
        func save(replying reply: StubReply) async throws {
            let server = StubServer { _ in reply }
            try await makeBackend(server).save(serverReport("A"))
        }
        await #expect(throws: CommunityError.rejected(.empty)) {
            try await save(replying: .json(422, #"{"error":{"code":"empty_report","message":""}}"#))
        }
        await #expect(throws: CommunityError.rejected(.objectionable)) {
            try await save(replying: .json(422, #"{"error":{"code":"invalid_note","reason":"objectionable","message":""}}"#))
        }
        await #expect(throws: CommunityError.rejected(.containsContact)) {
            try await save(replying: .json(422, #"{"error":{"code":"invalid_note","reason":"contains_contact","message":""}}"#))
        }
        // Everything else counts as done, so the queue moves on.
        try await save(replying: .json(422, #"{"error":{"code":"invalid_date","message":""}}"#))
        try await save(replying: .json(403, #"{"error":{"code":"forbidden","message":""}}"#))
        try await save(replying: .json(409, #"{"error":{"code":"id_conflict","message":""}}"#))
        try await save(replying: .json(401, #"{"error":{"code":"install_required","message":""}}"#))
    }

    @Test("Deleting and flagging go to their routes with the token; refusals are final")
    func deleteAndFlag() async throws {
        let server = StubServer { request in request.method == "DELETE" ? .json(403, "{}") : .reply(status: 204) }
        let backend = makeBackend(server)
        try await backend.delete(reportID: "7D2B7C54-3F0A-4C5E-8B6D-0E5C6C1B9A10")
        try await backend.flag(reportID: "7D2B7C54-3F0A-4C5E-8B6D-0E5C6C1B9A10", reason: "spam")

        let sent = server.requests
        #expect(sent[0].method == "DELETE")
        #expect(sent[0].path == "/v1/reports/7D2B7C54-3F0A-4C5E-8B6D-0E5C6C1B9A10")
        #expect(sent[0].header("X-Toret-Install") == token)
        #expect(sent[1].method == "POST")
        #expect(sent[1].path == "/v1/reports/7D2B7C54-3F0A-4C5E-8B6D-0E5C6C1B9A10/flag")
        #expect(sent[1].header("X-Toret-Install") == token)
        let body = try #require(try JSONSerialization.jsonObject(with: sent[1].body) as? [String: String])
        #expect(body == ["reason": "spam"])
    }

    // MARK: Availability and identity

    @Test("Ready when health answers; a recent success is trusted for a moment")
    func availability() async {
        let clock = TestClock()
        let server = StubServer { _ in .json(200, #"{"status":"ok","version":"1","catalogue":723}"#) }
        let backend = makeBackend(server, clock: clock)
        #expect(await backend.availability() == .ready)
        #expect(await backend.availability() == .ready)
        #expect(server.requests.count == 1)
        #expect(server.requests.first?.path == "/v1/health")

        clock.advance(31)
        #expect(await backend.availability() == .ready)
        #expect(server.requests.count == 2)
    }

    @Test("An unhealthy server is unavailable, and never signed out or restricted")
    func unhealthy() async {
        for reply in [StubReply.json(500, "{}"), .json(503, "{}"), .fail(.cannotConnectToHost), .json(404, "{}")] {
            let server = StubServer { _ in reply }
            let state = await makeBackend(server).availability()
            #expect(state == .unavailable)
            #expect(server.requests.count == 1, "the server was really asked")
        }
    }

    @Test("A failure after a success withdraws the trust")
    func failureWithdrawsReady() async throws {
        let server = StubServer { _ in list([]) }
        let backend = makeBackend(server)
        _ = try await backend.recent(limit: 50)
        #expect(await backend.availability() == .ready)
        server.respond { _ in .fail(.networkConnectionLost) }
        await #expect(throws: CommunityError.unavailable) { try await backend.recent(limit: 50) }
        #expect(await backend.availability() == .unavailable)
    }

    @Test("The account token is the install token, so the handle matches the server's")
    func accountToken() async {
        let server = StubServer()
        let value = await makeBackend(server).accountToken()
        #expect(value == token)
        #expect(AuthorHandle.make(from: token) == "Visitante E95596")
        #expect(server.requests.isEmpty)
    }

    @Test("The install token is read once, off the first use")
    func tokenReadOnce() async throws {
        let reads = Counter()
        let server = StubServer { _ in .json(201, "{}") }
        let backend = HTTPBackend(client: server.client(), installToken: { reads.increment(); return token })
        _ = await backend.accountToken()
        try await backend.save(serverReport("A"))
        try await backend.delete(reportID: "A")
        #expect(reads.value == 1)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

@Suite("Install token and handle")
struct InstallTokenTests {
    /// The vectors in docs/backend/api.md, section 7: the Go server derives the
    /// same handle from the same bytes.
    @Test("The handle matches the documented vectors", arguments: [
        ("5B0C6E0D-7F7B-4D5E-9E3A-2C1F8A4B9D10", "Visitante E95596",
         "e95596c1ef4bc56b8d89e5e4d03a56f3b5b58f9db22f72fd73515f60d650ddec"),
        ("00000000-0000-4000-8000-000000000000", "Visitante 75CD2D",
         "75cd2d95f28dc96de02dbc8b34854c178d5d220e458cd9acf715a6915e7766dc"),
    ])
    func vectors(token: String, handle: String, digest: String) {
        #expect(AuthorHandle.make(from: token) == handle)
        let sha = SHA256.hash(data: Data("toret.author.\(token)".utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(sha == digest)
    }

    @Test("Tokens must be 16 to 64 characters of letters, digits, dot, underscore, dash")
    func validity() {
        #expect(InstallToken.isValid(UUID().uuidString))
        #expect(InstallToken.isValid("abcdefghijklmnop"))
        #expect(InstallToken.isValid(String(repeating: "a", count: 64)))
        #expect(!InstallToken.isValid("short"))
        #expect(!InstallToken.isValid(String(repeating: "a", count: 65)))
        #expect(!InstallToken.isValid("has space in it 12345"))
        #expect(!InstallToken.isValid("accént-accént-accént"))
        #expect(!InstallToken.isValid(""))
    }

    @Test("A stored token wins; otherwise the install id seeds it; otherwise a new one is made")
    func resolving() {
        let stored = MemoryTokenStore("stored-token-0000000000")
        #expect(InstallToken.resolve(store: stored, seed: "seed-token-00000000000") == "stored-token-0000000000")

        let empty = MemoryTokenStore()
        #expect(InstallToken.resolve(store: empty, seed: "seed-token-00000000000") == "seed-token-00000000000")
        #expect(empty.read() == "seed-token-00000000000", "saved for next time")

        let unseeded = MemoryTokenStore()
        #expect(InstallToken.resolve(store: unseeded, seed: nil, generate: { "generated-0000000000" }) == "generated-0000000000")

        // An id the server would refuse is not used.
        let invalid = MemoryTokenStore()
        #expect(InstallToken.resolve(store: invalid, seed: "no", generate: { "generated-0000000000" }) == "generated-0000000000")

        // A damaged value in the store is replaced.
        let damaged = MemoryTokenStore("bad")
        #expect(InstallToken.resolve(store: damaged, seed: "seed-token-00000000000") == "seed-token-00000000000")
    }

    @Test("When the Keychain cannot be written the seed still gives the same token every launch")
    func keychainFails() {
        let broken = MemoryTokenStore(writable: false)
        let first = InstallToken.resolve(store: broken, seed: "seed-token-00000000000")
        let second = InstallToken.resolve(store: broken, seed: "seed-token-00000000000")
        #expect(first == second)
        #expect(first == "seed-token-00000000000")
    }

    @Test("The Keychain round-trips a token")
    func keychain() {
        let store = KeychainTokenStore(service: "br.tec.nuance.toret.tests.\(UUID().uuidString)", account: "token")
        defer { store.delete() }
        #expect(store.read() == nil)
        guard store.write("first-token-000000000") else {
            // A host with no usable Keychain: the fallback above covers it.
            return
        }
        #expect(store.read() == "first-token-000000000")
        #expect(store.write("second-token-00000000"))
        #expect(store.read() == "second-token-00000000")
    }
}

private final class MemoryTokenStore: InstallTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    private let writable: Bool

    init(_ value: String? = nil, writable: Bool = true) {
        self.value = value
        self.writable = writable
    }

    func read() -> String? { lock.withLock { value } }
    func write(_ token: String) -> Bool {
        guard writable else { return false }
        lock.withLock { value = token }
        return true
    }
}

@Suite("API configuration")
struct APIConfigurationTests {
    @Test("The default address is the production one")
    func defaultURL() {
        #expect(APIConfiguration.defaultBaseURL.absoluteString == "https://torino.deepdive.dev.br")
    }

    @Test("-toret-api names a server, and only a usable address counts")
    func override() {
        #expect(APIConfiguration.launchOverride(in: ["Toret", "-toret-api", "http://127.0.0.1:8099"])?.absoluteString == "http://127.0.0.1:8099")
        #expect(APIConfiguration.launchOverride(in: ["Toret"]) == nil)
        #expect(APIConfiguration.launchOverride(in: ["Toret", "-toret-api"]) == nil)
        #expect(APIConfiguration.launchOverride(in: ["Toret", "-toret-api", "ftp://example.com"]) == nil)
        #expect(APIConfiguration.launchOverride(in: ["Toret", "-toret-api", "not a url"]) == nil)
    }

    #if DEBUG
    @Test("A Debug build stays on the device unless a server is named")
    func debugDefault() {
        #expect(APIConfiguration.resolvedBaseURL(arguments: ["Toret"]) == nil)
        #expect(APIConfiguration.resolvedBaseURL(arguments: ["Toret", "-toret-api", "https://example.test"])?.host == "example.test")
    }
    #endif
}

// MARK: - The community store against the HTTP backend

@Suite("Community over HTTP")
@MainActor
struct CommunityOverHTTPTests {
    private func make(
        _ api: FakeAPI, clock: TestClock = TestClock(), persistence: InMemoryPersistence = InMemoryPersistence()
    ) -> Community {
        let client = api.server.client(clock: { clock.now })
        return Community(
            backend: HTTPBackend(client: client, installToken: { token }),
            persistence: persistence, clock: { clock.now }
        )
    }

    @Test("A report is sent, comes back under the server's handle, and is still mine")
    func sendAndRefresh() async {
        let api = FakeAPI()
        let community = make(api)
        await community.flush()
        #expect(community.availability == .ready)

        community.submit(ReportDraft(fountainID: "f1", state: .running, rating: 5, note: "Gelada"))
        #expect(await waitUntil { community.pendingCount == 0 && api.reports.count == 1 })
        #expect(api.reports.first?.author == AuthorHandle.make(from: token))

        await community.refresh()
        #expect(community.handle == AuthorHandle.make(from: token))
        let mine = community.reports(for: "f1")
        #expect(mine.count == 1)
        #expect(mine.first.map(community.isMine) == true)
    }

    @Test("A report written while the server is out of reach goes out when it is back")
    func offlineThenOnline() async {
        let api = FakeAPI()
        api.setOffline(true)
        let community = make(api)
        community.submit(ReportDraft(fountainID: "f1", state: .dry))
        await community.flush()
        #expect(community.availability == .unavailable)
        #expect(community.pendingCount == 1)
        #expect(community.reports(for: "f1").count == 1)

        api.setOffline(false)
        await community.flush()
        #expect(await waitUntil { community.pendingCount == 0 })
        #expect(api.reports.count == 1)
    }

    @Test("Deleting your own report removes it from the server")
    func deleting() async {
        let api = FakeAPI()
        let community = make(api)
        community.submit(ReportDraft(fountainID: "f1", state: .running))
        #expect(await waitUntil { api.reports.count == 1 && community.pendingCount == 0 })

        community.deleteMine(community.reports(for: "f1")[0])
        #expect(await waitUntil { api.reports.isEmpty && community.pendingCount == 0 })
        await community.refresh()
        #expect(community.reports(for: "f1").isEmpty)
    }

    @Test("Flagging goes to the server with the reason")
    func flagging() async {
        let api = FakeAPI()
        api.seed(serverReport("R1"))
        let community = make(api)
        await community.refresh()
        community.flag(community.reports(for: "f1")[0], reason: "offensive")
        #expect(await waitUntil { api.flags.count == 1 })
        #expect(api.flags.first?.reason == "offensive")
        #expect(api.flags.first?.install == token)
        #expect(community.reports(for: "f1").isEmpty)
    }

    @Test("A report the server refuses for good leaves the queue and the screen")
    func refused() async {
        let api = FakeAPI()
        // The app filters before it sends; a server that disagrees is final.
        api.server.respond { request in
            request.method == "POST"
                ? .json(422, #"{"error":{"code":"invalid_note","reason":"objectionable","message":""}}"#)
                : .json(200, #"{"status":"ok"}"#)
        }
        let community = make(api)
        community.submit(ReportDraft(fountainID: "f1", state: .running, note: "Gelada"))
        #expect(await waitUntil { community.pendingCount == 0 })
        #expect(community.reports(for: "f1").isEmpty)
    }

    @Test("A report told to wait stays queued and on screen")
    func waiting() async {
        let api = FakeAPI()
        api.server.respond { request in
            request.method == "POST"
                ? .json(429, "{}", headers: ["Retry-After": "1200"])
                : .json(200, #"{"status":"ok"}"#)
        }
        let community = make(api)
        community.submit(ReportDraft(fountainID: "f1", state: .running))
        #expect(await waitUntil { api.server.requests.contains { $0.method == "POST" } })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(community.pendingCount == 1)
        #expect(community.reports(for: "f1").count == 1)
    }

    @Test("A report sent a moment ago survives a download that does not list it yet")
    func readAfterWrite() async {
        let clock = TestClock()
        let api = FakeAPI()
        api.setLag(true)
        let community = make(api, clock: clock)
        community.submit(ReportDraft(fountainID: "f1", state: .running))
        #expect(await waitUntil { community.pendingCount == 0 && api.reports.count == 1 })

        await community.refresh()
        #expect(community.reports(for: "f1").count == 1, "the index has not caught up; the report is not deleted")

        // Past the settling time, absence means what it says.
        clock.advance(Community.settleTime + 1)
        await community.refresh()
        #expect(community.reports(for: "f1").isEmpty)
    }

    @Test("A report deleted a moment ago is not brought back by a stale download")
    func deleteAfterRead() async {
        let clock = TestClock()
        let api = FakeAPI()
        let community = make(api, clock: clock)
        community.submit(ReportDraft(fountainID: "f1", state: .running))
        #expect(await waitUntil { community.pendingCount == 0 && api.reports.count == 1 })
        await community.refresh()

        api.setLag(true)
        community.deleteMine(community.reports(for: "f1")[0])
        #expect(await waitUntil { community.pendingCount == 0 })
        await community.refresh()
        #expect(community.reports(for: "f1").isEmpty, "the index still lists it; the delete wins")

        api.settle()
        clock.advance(Community.settleTime + 1)
        await community.refresh()
        #expect(community.reports(for: "f1").isEmpty)
    }

    @Test("A failed refresh offline keeps what was downloaded")
    func offlineRefresh() async {
        let api = FakeAPI()
        api.seed(serverReport("R1"))
        let community = make(api)
        await community.refresh()
        api.setOffline(true)
        await community.refresh()
        #expect(community.lastRefreshFailed)
        #expect(community.feed.map(\.id) == ["R1"])
    }
}
