import Foundation
import Testing

@testable import Toret

/// A backend whose network can be switched off, and which records what reached it.
actor FakeBackend: CommunityBackend {
    nonisolated let isShared: Bool
    private var availabilityValue: CommunityAvailability
    private var token: String?
    private(set) var stored: [Report] = []
    private(set) var flags: [(String, String)] = []
    private(set) var deleted: [String] = []
    private var failing = false
    private(set) var saveAttempts = 0

    init(shared: Bool = true, availability: CommunityAvailability = .ready, token: String? = "account-1") {
        isShared = shared
        availabilityValue = availability
        self.token = token
    }

    func setOffline(_ offline: Bool) { failing = offline }
    func setAvailability(_ value: CommunityAvailability) { availabilityValue = value }
    func seed(_ reports: [Report]) { stored.append(contentsOf: reports) }
    func remove(_ id: String) { stored.removeAll { $0.id == id } }

    func availability() async -> CommunityAvailability { availabilityValue }
    func accountToken() async -> String? { token }

    func recent(limit: Int) async throws -> [Report] {
        if failing { throw CommunityError.unavailable }
        return Array(stored.sorted { $0.date > $1.date }.prefix(limit))
    }

    func reports(for fountainID: String, limit: Int) async throws -> [Report] {
        if failing { throw CommunityError.unavailable }
        return Array(stored.filter { $0.fountainID == fountainID }.sorted { $0.date > $1.date }.prefix(limit))
    }

    func save(_ report: Report) async throws {
        saveAttempts += 1
        if failing { throw CommunityError.unavailable }
        stored.removeAll { $0.id == report.id }
        stored.append(report)
    }

    func delete(reportID: String) async throws {
        if failing { throw CommunityError.unavailable }
        stored.removeAll { $0.id == reportID }
        deleted.append(reportID)
    }

    func flag(reportID: String, reason: String) async throws {
        if failing { throw CommunityError.unavailable }
        flags.append((reportID, reason))
    }
}

final class InMemoryPersistence: CommunityPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var state: CommunityState?

    func load() -> CommunityState? { lock.withLock { state } }
    func save(_ state: CommunityState) { lock.withLock { self.state = state } }
}

/// A clock a test can wind forward.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { value = start }
    var now: Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}

@MainActor
private func makeCommunity(
    backend: FakeBackend = FakeBackend(),
    persistence: InMemoryPersistence = InMemoryPersistence(),
    clock: TestClock = TestClock()
) -> Community {
    Community(backend: backend, persistence: persistence, clock: { clock.now })
}

private func remoteReport(
    _ id: String, fountain: String = "f1", state: WaterState = .running,
    author: String = "Visitante AAAAAA", note: String = "", rating: Int? = nil,
    at date: Date = Date(timeIntervalSince1970: 1_800_000_000)
) -> Report {
    Report(
        id: id, fountainID: fountain, state: state, rating: rating, note: note,
        date: date, author: author, isMine: false
    )
}

@Suite("Community store")
@MainActor
struct CommunityStoreTests {
    @Test("A submitted report shows at once and is uploaded")
    func submitIsOptimisticThenSent() async {
        let backend = FakeBackend()
        let community = makeCommunity(backend: backend)

        let result = community.submit(ReportDraft(fountainID: "f1", state: .running, rating: 4))
        #expect(result == .accepted(.waitingForConnection) || result == .accepted(.sending))
        #expect(community.reports(for: "f1").count == 1)
        #expect(community.summary(for: "f1").state == .running)

        await community.flush()
        #expect(await backend.stored.count == 1)
        #expect(community.pendingCount == 0)
    }

    @Test("Offline, a report waits and goes out when the network returns")
    func queuedWhileOffline() async {
        let backend = FakeBackend()
        await backend.setOffline(true)
        let community = makeCommunity(backend: backend)

        community.submit(ReportDraft(fountainID: "f1", state: .dry))
        await community.flush()
        #expect(community.pendingCount == 1)
        #expect(await backend.stored.isEmpty)
        // Still on screen, and still marked as waiting.
        #expect(community.reports(for: "f1").count == 1)
        #expect(community.isPending(community.reports(for: "f1")[0]))

        await backend.setOffline(false)
        await community.flush()
        #expect(community.pendingCount == 0)
        #expect(await backend.stored.count == 1)
    }

    @Test("Without an iCloud account nothing is sent, and nothing is lost")
    func signedOut() async {
        let backend = FakeBackend(availability: .signedOut, token: nil)
        let community = makeCommunity(backend: backend)

        // The app has already refreshed by the time anyone can open the sheet, so
        // availability is known. Before that first flush it is not, and a shared
        // backend says "waiting for a connection" rather than guessing.
        #expect(community.delivery == .waitingForConnection)
        await community.flush()
        #expect(community.availability == .signedOut)

        let result = community.submit(ReportDraft(fountainID: "f1", state: .running))
        #expect(result == .accepted(.waitingForICloud))
        #expect(community.delivery == .waitingForICloud)
        await community.flush()
        #expect(await backend.saveAttempts == 0)
        #expect(community.pendingCount == 1)

        await backend.setAvailability(.ready)
        await community.flush()
        #expect(await backend.stored.count == 1)
    }

    @Test("A device-only build says so and keeps the report")
    func deviceOnly() async {
        let backend = FakeBackend(shared: false, availability: .localOnly, token: nil)
        let community = makeCommunity(backend: backend)
        #expect(community.submit(ReportDraft(fountainID: "f1", state: .weak)) == .accepted(.deviceOnly))
        await community.flush()
        #expect(await backend.stored.count == 1)
    }

    @Test("One report per fountain per half hour")
    func rateLimit() {
        let clock = TestClock()
        let community = makeCommunity(clock: clock)
        #expect(community.submit(ReportDraft(fountainID: "f1", state: .running)) != .rejected(.empty))

        let blocked = community.submit(ReportDraft(fountainID: "f1", state: .dry))
        guard case let .rejected(.rateLimited(minutes)) = blocked else {
            Issue.record("expected a rate limit, got \(blocked)")
            return
        }
        #expect(minutes == 30)

        // Another fountain is a different conversation.
        #expect(community.submit(ReportDraft(fountainID: "f2", state: .dry)) != .rejected(.rateLimited(minutesLeft: 30)))

        clock.advance(31 * 60)
        guard case .accepted = community.submit(ReportDraft(fountainID: "f1", state: .dry)) else {
            Issue.record("the limit should have lapsed")
            return
        }
    }

    @Test("A draft with nothing in it is refused")
    func empty() {
        let community = makeCommunity()
        #expect(community.submit(ReportDraft(fountainID: "f1")) == .rejected(.empty))
        #expect(community.submit(ReportDraft(fountainID: "f1", rating: 3)) != .rejected(.empty))
    }

    @Test("Objectionable notes and contact details are refused")
    func noteFilter() {
        let community = makeCommunity()
        #expect(community.submit(ReportDraft(fountainID: "a", state: .running, note: "que merda de f0da puta")) == .rejected(.objectionable))
        #expect(community.submit(ReportDraft(fountainID: "b", state: .running, note: "veja www.exemplo.com")) == .rejected(.containsContact))
        #expect(community.submit(ReportDraft(fountainID: "c", state: .running, note: "me ligue 11 99999-1234")) == .rejected(.containsContact))
        #expect(community.submit(ReportDraft(fountainID: "d", state: .running, note: "Água gelada, sem fila")) == .accepted(community.delivery))
    }

    /// A rating with no word about the water must not turn "running" into "unknown".
    @Test("A rating-only report leaves the water state alone")
    func ratingOnly() {
        let clock = TestClock()
        let community = makeCommunity(clock: clock)
        community.submit(ReportDraft(fountainID: "f1", state: .running))
        clock.advance(31 * 60)
        community.submit(ReportDraft(fountainID: "f1", state: nil, rating: 5))
        let summary = community.summary(for: "f1")
        #expect(summary.state == .running)
        #expect(summary.average == 5)
    }

    @Test("Reporting a report hides it at once and tells the backend")
    func flagging() async {
        let backend = FakeBackend()
        await backend.seed([remoteReport("r1")])
        let community = makeCommunity(backend: backend)
        await community.refresh()
        #expect(community.reports(for: "f1").count == 1)

        community.flag(community.reports(for: "f1")[0], reason: "spam")
        #expect(community.reports(for: "f1").isEmpty)
        #expect(community.feed.isEmpty)
        await community.flush()
        #expect(await backend.flags.count == 1)
    }

    @Test("Blocking an author hides all of theirs, and unblocking restores them")
    func blocking() async {
        let backend = FakeBackend()
        await backend.seed([
            remoteReport("r1", author: "Visitante BBBBBB"),
            remoteReport("r2", fountain: "f2", author: "Visitante BBBBBB"),
            remoteReport("r3", author: "Visitante CCCCCC"),
        ])
        let community = makeCommunity(backend: backend)
        await community.refresh()
        #expect(community.feed.count == 3)

        community.block(author: "Visitante BBBBBB")
        #expect(community.feed.map(\.id) == ["r3"])
        #expect(community.blockedAuthors == ["Visitante BBBBBB"])

        community.unblock(author: "Visitante BBBBBB")
        #expect(community.feed.count == 3)
    }

    @Test("You cannot block or report yourself")
    func notYourself() {
        let community = makeCommunity()
        community.submit(ReportDraft(fountainID: "f1", state: .running))
        let mine = community.reports(for: "f1")[0]
        community.block(author: mine.author)
        community.flag(mine, reason: "spam")
        #expect(community.reports(for: "f1").count == 1)
        #expect(community.blockedAuthors.isEmpty)
    }

    @Test("A report that slipped into the database but fails the filter is not shown")
    func incomingIsFiltered() async {
        let backend = FakeBackend()
        await backend.seed([
            remoteReport("ok", note: "Água gelada"),
            remoteReport("bad", note: "visite www.spam.com"),
        ])
        let community = makeCommunity(backend: backend)
        await community.refresh()
        #expect(community.feed.map(\.id) == ["ok"])
    }

    @Test("Deleting your own report removes it, locally and remotely")
    func deleteMine() async {
        let backend = FakeBackend()
        let community = makeCommunity(backend: backend)
        community.submit(ReportDraft(fountainID: "f1", state: .running))
        await community.flush()
        let mine = community.reports(for: "f1")[0]
        #expect(community.isMine(mine))

        community.deleteMine(mine)
        #expect(community.reports(for: "f1").isEmpty)
        await community.flush()
        #expect(await backend.stored.isEmpty)
        #expect(await backend.deleted == [mine.id])
    }

    @Test("Deleting a report that never left the device never touches the backend")
    func deleteUnsent() async {
        let backend = FakeBackend()
        await backend.setOffline(true)
        let community = makeCommunity(backend: backend)
        community.submit(ReportDraft(fountainID: "f1", state: .running))
        community.deleteMine(community.reports(for: "f1")[0])
        await community.flush()
        #expect(community.pendingCount == 0)
        #expect(await backend.deleted.isEmpty)
    }

    @Test("Someone else's report cannot be deleted from here")
    func deleteOthers() async {
        let backend = FakeBackend()
        await backend.seed([remoteReport("r1")])
        let community = makeCommunity(backend: backend)
        await community.refresh()
        community.deleteMine(community.reports(for: "f1")[0])
        #expect(community.reports(for: "f1").count == 1)
    }

    @Test("A report deleted elsewhere disappears at the next refresh")
    func remoteDeletion() async {
        let backend = FakeBackend()
        await backend.seed([remoteReport("r1"), remoteReport("r2")])
        let community = makeCommunity(backend: backend)
        await community.refresh()
        #expect(community.feed.count == 2)

        await backend.remove("r1")
        await community.refresh()
        #expect(community.feed.map(\.id) == ["r2"])
    }

    @Test("A failed refresh keeps what was downloaded and says so")
    func offlineRefresh() async {
        let backend = FakeBackend()
        await backend.seed([remoteReport("r1")])
        let community = makeCommunity(backend: backend)
        await community.refresh()
        await backend.setOffline(true)
        await community.refresh()
        #expect(community.lastRefreshFailed)
        #expect(community.feed.count == 1)
    }

    @Test("Everything survives a relaunch")
    func persistence() async {
        let persistence = InMemoryPersistence()
        let backend = FakeBackend()
        await backend.setOffline(true)
        let first = makeCommunity(backend: backend, persistence: persistence)
        first.submit(ReportDraft(fountainID: "f1", state: .weak, rating: 3, tags: [.cold], note: "Fio de água"))
        first.block(author: "Visitante DDDDDD")

        let second = makeCommunity(backend: backend, persistence: persistence)
        #expect(second.reports(for: "f1").count == 1)
        #expect(second.pendingCount == 1)
        #expect(second.blockedAuthors == ["Visitante DDDDDD"])
        #expect(second.handle == first.handle)
        // And the rate limit is remembered, so quitting the app does not reset it.
        #expect(second.submit(ReportDraft(fountainID: "f1", state: .dry)) != .accepted(second.delivery))
    }

    @Test("Learning the iCloud account re-signs the queue under the account's handle")
    func adoptsAccount() async {
        let backend = FakeBackend(availability: .signedOut, token: nil)
        let persistence = InMemoryPersistence()
        let community = makeCommunity(backend: backend, persistence: persistence)
        let installHandle = community.handle
        community.submit(ReportDraft(fountainID: "f1", state: .running))
        #expect(community.reports(for: "f1")[0].author == installHandle)

        let signedIn = FakeBackend(availability: .ready, token: "account-9")
        let after = makeCommunity(backend: signedIn, persistence: persistence)
        await after.flush()
        #expect(after.handle == AuthorHandle.make(from: "account-9"))
        #expect(after.handle != installHandle)
        let sent = await signedIn.stored
        #expect(sent.count == 1)
        #expect(sent[0].author == after.handle)
        // Still recognised as the user's own.
        #expect(after.isMine(after.reports(for: "f1")[0]))
    }

    @Test("Top tags are the ones most often given")
    func topTags() async {
        let backend = FakeBackend()
        func tagged(_ id: String, _ tags: [ReportTag]) -> Report {
            Report(id: id, fountainID: "f1", state: .running, tags: tags,
                   date: Date(timeIntervalSince1970: 1_800_000_000), author: "Visitante AAAAAA", isMine: false)
        }
        await backend.seed([tagged("1", [.cold, .clean]), tagged("2", [.cold]), tagged("3", [.cold, .shade])])
        let community = makeCommunity(backend: backend)
        await community.refresh()
        #expect(community.topTags(for: "f1").first == .cold)
    }
}

@Suite("Author handle and note filter")
struct IdentityAndFilterTests {
    @Test("The handle is stable, anonymous and shaped like a name")
    func handle() {
        let a = AuthorHandle.make(from: "abc")
        #expect(a == AuthorHandle.make(from: "abc"))
        #expect(a != AuthorHandle.make(from: "abd"))
        #expect(a.hasPrefix("Visitante "))
        #expect(!a.contains("abc"))
        #expect(a.count == "Visitante ".count + 6)
    }

    @Test("Ordinary notes pass, in three languages")
    func ordinary() {
        for note in ["Água gelada e fila pequena", "Acqua fresca, ottimo getto", "Cold water, easy to reach", ""] {
            #expect(NoteFilter.check(note) == .ok)
        }
    }

    @Test("Whole words only")
    func wholeWords() {
        #expect(NoteFilter.check("Fonte de Scunthorpe") == .ok)
        #expect(NoteFilter.check("Computador, putamente bom") == .ok)
    }

    @Test("Links, handles and numbers are contact details")
    func contact() {
        #expect(NoteFilter.check("https://exemplo.com") == .containsContact)
        #expect(NoteFilter.check("fale comigo @fulano_123") == .containsContact)
        #expect(NoteFilter.check("+39 011 123 4567") == .containsContact)
        #expect(NoteFilter.check("A fonte fica a 50 m do ponto") == .ok)
    }
}

@Suite("Local backend")
struct LocalBackendTests {
    @Test("Reports saved to the file come back, newest first, and can be deleted")
    func roundTrip() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("toret-local-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let backend = LocalBackend(url: url)

        try await backend.save(remoteReport("old", at: Date(timeIntervalSince1970: 1_000)))
        try await backend.save(remoteReport("new", at: Date(timeIntervalSince1970: 2_000)))
        try await backend.save(remoteReport("new", at: Date(timeIntervalSince1970: 2_000)))
        #expect(try await backend.recent(limit: 10).map(\.id) == ["new", "old"])
        #expect(try await backend.reports(for: "other", limit: 10).isEmpty)

        try await backend.delete(reportID: "new")
        try await backend.delete(reportID: "new")
        #expect(try await backend.recent(limit: 10).map(\.id) == ["old"])
    }

    @Test("The state file round-trips through disk")
    func fileState() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("toret-state-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let persistence = FilePersistence(url: url)
        var state = CommunityState()
        state.blocked = ["Visitante EEEEEE"]
        state.known = [remoteReport("r1", note: "Gelada")]
        persistence.save(state)
        #expect(persistence.load() == state)
    }
}
