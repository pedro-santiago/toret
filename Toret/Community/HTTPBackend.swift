import Foundation

/// The shared community: the Toret API (`docs/backend/api.md`), a small server of
/// ours that stores reports and hands them to everyone.
///
/// There are no accounts. A write carries a random install token, kept in the
/// Keychain, which the server hashes before storing and from which it derives the
/// same "Visitante XXXXXX" handle ``AuthorHandle`` does, so blocking and "mine"
/// agree on both sides. Nothing here waits for the network on the main actor: a
/// call that cannot get through throws, and ``Community`` keeps the report in its
/// queue and tries again.
actor HTTPBackend: CommunityBackend {
    nonisolated let isShared = true

    private let client: APIClient
    private let tokenSource: @Sendable () -> String
    private var resolvedToken: String?

    /// How long a successful call vouches for the server, so that a flush right
    /// after a refresh does not probe `/v1/health` again.
    private static let availabilityFreshness: TimeInterval = 30

    init(client: APIClient, installToken: @escaping @Sendable () -> String) {
        self.client = client
        tokenSource = installToken
    }

    /// The real thing. `seed` is the install id the community file already holds,
    /// so the handle other people have seen does not change.
    init(baseURL: URL, seed: String?) {
        self.init(client: APIClient(baseURL: baseURL)) {
            InstallToken.resolve(store: KeychainTokenStore(), seed: seed)
        }
    }

    // MARK: Identity and health

    func availability() async -> CommunityAvailability {
        if await client.reachedServer(within: Self.availabilityFreshness) { return .ready }
        guard let response = try? await client.send("GET", "/v1/health"), response.status == 200 else {
            return .unavailable
        }
        return .ready
    }

    func accountToken() async -> String? { token() }

    /// Read from the Keychain on first use, off the main actor, and not again.
    private func token() -> String {
        if let resolvedToken { return resolvedToken }
        let token = tokenSource()
        resolvedToken = token
        return token
    }

    // MARK: Reading

    func recent(limit: Int) async throws -> [Report] {
        try await list("/v1/reports", limit: limit)
    }

    func reports(for fountainID: String, limit: Int) async throws -> [Report] {
        try await list("/v1/fountains/\(Self.segment(fountainID))/reports", limit: limit)
    }

    /// Anything but a well-formed list is a failure, never an empty list: the
    /// community store reads a short download as "this is everything" and drops
    /// the reports it did not see, so an error page must not look like "none".
    private func list(_ path: String, limit: Int) async throws -> [Report] {
        let response = try await client.send("GET", path, query: [URLQueryItem(name: "limit", value: String(limit))])
        guard response.status == 200,
              let list = try? FilePersistence.decoder.decode(WireReportList.self, from: response.data)
        else { throw CommunityError.unavailable }
        return list.reports.compactMap(\.report)
    }

    // MARK: Writing

    func save(_ report: Report) async throws {
        let body = try FilePersistence.encoder.encode(WireReport(report))
        let response: APIClient.Response
        do {
            response = try await client.send("POST", "/v1/reports", body: body, headers: writeHeaders())
        } catch CommunityError.retryLater(let seconds, true) {
            throw CommunityError.rejected(.rateLimited(minutesLeft: max(1, (seconds + 59) / 60)))
        }
        switch response.status {
        case 200, 201:
            return
        case 422:
            if let rejection = Self.rejection(in: response.data) { throw CommunityError.rejected(rejection) }
        default:
            break
        }
        // Any other refusal is final (a banned install, an id taken by someone
        // else): the queue must move on, so the call counts as done.
    }

    func delete(reportID: String) async throws {
        _ = try await client.send("DELETE", "/v1/reports/\(Self.segment(reportID))", headers: writeHeaders())
    }

    func flag(reportID: String, reason: String) async throws {
        let body = try JSONEncoder().encode(["reason": reason])
        _ = try await client.send(
            "POST", "/v1/reports/\(Self.segment(reportID))/flag", body: body, headers: writeHeaders()
        )
    }

    // MARK: Internals

    private func writeHeaders() -> [String: String] {
        ["X-Toret-Install": token()]
    }

    private static func segment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? value
    }

    /// The rejections the sheet has words for. Anything else is dropped quietly.
    static func rejection(in data: Data) -> SubmitRejection? {
        guard let envelope = try? JSONDecoder().decode(WireError.self, from: data) else { return nil }
        switch (envelope.error.code, envelope.error.reason) {
        case ("empty_report", _): return .empty
        case ("invalid_note", "objectionable"?): return .objectionable
        case ("invalid_note", "contains_contact"?): return .containsContact
        default: return nil
        }
    }
}

// MARK: Wire shapes

/// A report as the server takes it: no author and no `isMine`, which the server
/// ignores in any case.
private struct WireReport: Encodable {
    let id: String
    let fountainID: String
    let state: WaterState
    let rating: Int?
    let tags: [ReportTag]
    let note: String
    let date: Date

    init(_ report: Report) {
        id = report.id
        fountainID = report.fountainID
        state = report.state
        rating = report.rating
        tags = report.tags
        note = report.note
        date = report.date
    }
}

/// One report out of a list. A record this app cannot read (a value from a newer
/// server, a missing field) is dropped on its own instead of failing the list.
private struct LossyReport: Decodable {
    let report: Report?

    private struct Fields: Decodable {
        let id: String
        let fountainID: String
        let state: WaterState
        let rating: Int?
        let tags: [String]?
        let note: String?
        let date: Date
        let author: String?
    }

    init(from decoder: any Decoder) throws {
        guard let fields = try? Fields(from: decoder) else {
            report = nil
            return
        }
        report = Report(
            id: fields.id, fountainID: fields.fountainID, state: fields.state,
            rating: fields.rating.flatMap { $0 > 0 ? $0 : nil },
            tags: Array((fields.tags ?? []).compactMap(ReportTag.init(rawValue:)).prefix(3)),
            note: fields.note ?? "", date: fields.date,
            author: fields.author ?? "Visitante", isMine: false
        )
    }
}

private struct WireReportList: Decodable {
    let reports: [LossyReport]
}

private struct WireError: Decodable {
    struct Body: Decodable {
        let code: String
        let reason: String?
    }

    let error: Body
}
