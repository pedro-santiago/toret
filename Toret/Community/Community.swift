import Foundation
import Network
import Observation

/// What a person fills in to report on a fountain.
struct ReportDraft: Equatable, Sendable {
    var fountainID: String
    /// What the water is doing. Nil when they only want to rate it.
    var state: WaterState?
    /// 1...5, or 0 for none.
    var rating: Int = 0
    var tags: [ReportTag] = []
    var note: String = ""
}

/// Why a draft was turned away, in terms the sheet can say out loud.
enum SubmitRejection: Equatable, Sendable {
    /// Neither a state nor a rating: nothing to say.
    case empty
    case objectionable
    case containsContact
    /// This device reported on this fountain a moment ago.
    case rateLimited(minutesLeft: Int)
}

/// What will happen to a report that was accepted, decided at the moment it was.
enum SubmitDelivery: Equatable, Sendable {
    /// Going to the shared database now.
    case sending
    /// Kept here until there is an iCloud account to send it from.
    case waitingForICloud
    /// Kept here until iCloud can be reached.
    case waitingForConnection
    /// This build shares nothing; the report lives on the device.
    case deviceOnly
}

enum SubmitResult: Equatable, Sendable {
    case accepted(SubmitDelivery)
    case rejected(SubmitRejection)
}

/// The community feature's single source of truth.
///
/// Offline-first and optimistic: a report appears the instant it is submitted,
/// goes into a queue, and is uploaded whenever the backend can take it. Nothing
/// here waits on the network for the interface — every public method returns
/// straight away and the slow work happens in tasks that fold their results back
/// in. The backend is a protocol so the real database can be absent (Debug
/// builds), unreachable (a metro tunnel) or faked (tests) without a code path
/// that only runs in production.
@MainActor
@Observable
final class Community {
    /// One report per fountain per device per half hour.
    ///
    /// Enough to correct a mistake or add a line; too slow to flood a fountain
    /// with a hundred ratings.
    static let rateLimit: TimeInterval = 30 * 60
    /// How far back the city feed reaches.
    static let feedWindow: TimeInterval = 30 * 86400
    private static let cacheLimit = 600
    private static let feedFetchLimit = 200
    private static let fountainFetchLimit = 40

    /// Every visible report from the last month, newest first.
    private(set) var feed: [Report] = []
    /// What each fountain's visible reports add up to.
    private(set) var summaries: [String: CommunitySummary] = [:]
    private(set) var availability: CommunityAvailability
    private(set) var isRefreshing = false
    /// True when the last refresh could not reach the database, so the screen can
    /// say it is showing what was last downloaded.
    private(set) var lastRefreshFailed = false
    /// Reports and deletions waiting to be uploaded.
    private(set) var pendingCount = 0
    /// The anonymous name this device reports under.
    private(set) var handle: String
    /// Authors this user blocked, for the list that lets them undo it.
    private(set) var blockedAuthors: [String] = []

    @ObservationIgnored private let backend: any CommunityBackend
    @ObservationIgnored private let persistence: any CommunityPersistence
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private var state: CommunityState
    @ObservationIgnored private var byFountain: [String: [Report]] = [:]
    @ObservationIgnored private var isFlushing = false
    @ObservationIgnored private var monitor: NWPathMonitor?

    /// True when what is submitted here is visible to other people.
    var isShared: Bool { backend.isShared }

    init(
        backend: any CommunityBackend,
        persistence: any CommunityPersistence,
        clock: @escaping @Sendable () -> Date = { .now }
    ) {
        self.backend = backend
        self.persistence = persistence
        self.clock = clock
        let restored = persistence.load() ?? CommunityState()
        state = restored
        availability = backend.isShared ? .unavailable : .localOnly
        handle = AuthorHandle.make(from: restored.accountToken ?? restored.installID)
        rebuild()
    }

    /// The real thing: CloudKit when this build was signed for it, a file otherwise.
    static func standard() -> Community {
        let container = Bundle.main.object(forInfoDictionaryKey: "ToretCloudContainer") as? String
        let backend: any CommunityBackend = (container?.isEmpty == false)
            ? CloudKitBackend(containerIdentifier: container!)
            : LocalBackend()
        return Community(backend: backend, persistence: FilePersistence())
    }

    // MARK: Reading

    /// The visible reports about one fountain, newest first.
    func reports(for fountainID: String) -> [Report] { byFountain[fountainID] ?? [] }

    func summary(for fountainID: String) -> CommunitySummary { summaries[fountainID] ?? .empty }

    /// Whether this device wrote the report. A report written before an iCloud
    /// account was known carries the install's handle, so both count.
    func isMine(_ report: Report) -> Bool {
        report.author == handle || report.author == installHandle
    }

    func isPending(_ report: Report) -> Bool { state.pending.contains(report.id) }

    /// The tags most often given to a fountain, for the chips under its rating.
    func topTags(for fountainID: String, limit: Int = 3) -> [ReportTag] {
        var counts: [ReportTag: Int] = [:]
        for tag in reports(for: fountainID).flatMap(\.tags) { counts[tag, default: 0] += 1 }
        return counts
            .sorted { ($0.value, $1.key.rawValue) > ($1.value, $0.key.rawValue) }
            .prefix(limit)
            .map(\.key)
    }

    /// What the sheet should say about where a report will go.
    var delivery: SubmitDelivery {
        switch availability {
        case .localOnly: .deviceOnly
        case .ready: .sending
        case .signedOut: .waitingForICloud
        case .restricted, .unavailable: .waitingForConnection
        }
    }

    // MARK: Writing

    /// Accepts a report, or says why not. Returns immediately; the upload is
    /// not waited for.
    @discardableResult
    func submit(_ draft: ReportDraft) -> SubmitResult {
        let rating = min(5, max(0, draft.rating))
        guard draft.state != nil || rating > 0 else { return .rejected(.empty) }

        switch NoteFilter.check(draft.note) {
        case .ok: break
        case .objectionable: return .rejected(.objectionable)
        case .containsContact: return .rejected(.containsContact)
        }

        let now = clock()
        if let last = state.lastSubmitted[draft.fountainID] {
            let left = Self.rateLimit - now.timeIntervalSince(last)
            if left > 0 { return .rejected(.rateLimited(minutesLeft: Int((left / 60).rounded(.up)))) }
        }

        let report = Report(
            fountainID: draft.fountainID,
            state: draft.state ?? .unknown,
            rating: rating > 0 ? rating : nil,
            tags: Array(draft.tags.prefix(3)),
            note: draft.note,
            date: now,
            author: handle
        )
        state.known.append(report)
        state.pending.append(report.id)
        state.lastSubmitted[draft.fountainID] = now
        commit()
        Task { await flush() }
        return .accepted(delivery)
    }

    /// Removes one of this device's own reports.
    func deleteMine(_ report: Report) {
        guard isMine(report) else { return }
        state.known.removeAll { $0.id == report.id }
        if let queued = state.pending.firstIndex(of: report.id) {
            // Never left the device: nothing to undo anywhere else.
            state.pending.remove(at: queued)
        } else {
            state.pendingDeletes.append(report.id)
        }
        commit()
        Task { await flush() }
    }

    /// Reports someone else's report as offensive and hides it here at once.
    func flag(_ report: Report, reason: String) {
        guard !isMine(report) else { return }
        state.hidden.append(report.id)
        state.pendingFlags.append(.init(reportID: report.id, reason: reason))
        commit()
        Task { await flush() }
    }

    /// Hides everything by this author, now and from here on.
    func block(author: String) {
        guard author != handle, author != installHandle, !state.blocked.contains(author) else { return }
        state.blocked.append(author)
        commit()
    }

    func unblock(author: String) {
        state.blocked.removeAll { $0 == author }
        commit()
    }

    // MARK: Syncing

    /// Uploads what is queued, then downloads the city feed.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await flush()
        do {
            let remote = try await backend.recent(limit: Self.feedFetchLimit)
            merge(remote, limit: Self.feedFetchLimit, scope: nil)
            lastRefreshFailed = false
        } catch {
            lastRefreshFailed = true
        }
        commit()
    }

    /// Downloads one fountain's reports, for its detail screen.
    func refresh(fountainID: String) async {
        await flush()
        do {
            let remote = try await backend.reports(for: fountainID, limit: Self.fountainFetchLimit)
            merge(remote, limit: Self.fountainFetchLimit, scope: fountainID)
            lastRefreshFailed = false
        } catch {
            lastRefreshFailed = true
        }
        commit()
    }

    /// Sends the queue, stopping at the first failure: if one upload cannot get
    /// through, the rest cannot either, and the order of the queue is worth keeping.
    func flush() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        availability = await backend.availability()
        if let token = await backend.accountToken(), token != state.accountToken {
            adopt(accountToken: token)
        }
        guard !backend.isShared || availability == .ready else {
            commit()
            return
        }

        for id in state.pending {
            guard let report = state.known.first(where: { $0.id == id }) else {
                state.pending.removeAll { $0 == id }
                continue
            }
            do {
                try await backend.save(report)
                state.pending.removeAll { $0 == id }
            } catch {
                break
            }
        }
        for id in state.pendingDeletes {
            do {
                try await backend.delete(reportID: id)
                state.pendingDeletes.removeAll { $0 == id }
            } catch {
                break
            }
        }
        for flag in state.pendingFlags {
            do {
                try await backend.flag(reportID: flag.reportID, reason: flag.reason)
                state.pendingFlags.removeAll { $0 == flag }
            } catch {
                break
            }
        }
        commit()
    }

    /// Starts uploading the moment the network comes back, so a report written
    /// in a tunnel is sent when the train comes out of it.
    func startMonitoring() {
        guard monitor == nil, backend.isShared else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await self?.flush() }
        }
        monitor.start(queue: DispatchQueue(label: "toret.community.path"))
        self.monitor = monitor
    }

    /// Re-derives the summaries against the clock. A report's state expires with
    /// time, and nothing else would tell the pins.
    func recompute() {
        rebuild()
    }

    // MARK: Internals

    private var installHandle: String { AuthorHandle.make(from: state.installID) }

    /// Learns which iCloud account this is. Reports written before that carry the
    /// install's handle and have not been uploaded; they go out under the account's.
    private func adopt(accountToken token: String) {
        state.accountToken = token
        let previous = handle
        handle = AuthorHandle.make(from: token)
        guard previous != handle else { return }
        let queued = Set(state.pending)
        state.known = state.known.map { report in
            guard queued.contains(report.id), report.author == previous || report.author == installHandle
            else { return report }
            return Report(
                id: report.id, fountainID: report.fountainID, state: report.state,
                rating: report.rating, tags: report.tags, note: report.note,
                date: report.date, author: handle
            )
        }
    }

    /// Folds a download into what is known. The database wins over the cache; a
    /// report that is in the cache and missing from a complete download has been
    /// deleted, and goes; one this device is about to upload or delete is left alone.
    private func merge(_ remote: [Report], limit: Int, scope: String?) {
        let remoteIDs = Set(remote.map(\.id))
        let oldest = remote.map(\.date).min()
        let complete = remote.count < limit
        let deleting = Set(state.pendingDeletes)
        let pending = Set(state.pending)

        var kept = state.known.filter { report in
            if let scope, report.fountainID != scope { return true }
            if remoteIDs.contains(report.id) || pending.contains(report.id) { return true }
            // Missing from the download: gone, unless the download did not reach
            // back far enough to have contained it.
            if complete { return false }
            return oldest.map { report.date < $0 } ?? true
        }
        let have = Set(kept.map(\.id))
        for report in remote where !deleting.contains(report.id) {
            if have.contains(report.id) {
                if let index = kept.firstIndex(where: { $0.id == report.id }) { kept[index] = report }
            } else {
                kept.append(report)
            }
        }
        state.known = kept
    }

    /// The reports the user can see: not hidden, not by a blocked author, and
    /// clean by the same filter the note field applies — a report that went into
    /// the database some other way is held to the standard of one written here.
    private func isVisible(_ report: Report) -> Bool {
        if state.hidden.contains(report.id) { return false }
        if state.blocked.contains(report.author), !isMine(report) { return false }
        return isMine(report) || NoteFilter.check(report.note) == .ok
    }

    private func rebuild() {
        let now = clock()
        let visible = state.known.filter(isVisible)
        byFountain = Dictionary(grouping: visible, by: \.fountainID)
            .mapValues { $0.sorted { $0.date > $1.date } }
        summaries = byFountain.mapValues { CommunitySummary.summarising($0, now: now) }
        feed = visible
            .filter { now.timeIntervalSince($0.date) <= Self.feedWindow }
            .sorted { $0.date > $1.date }
        pendingCount = state.pending.count + state.pendingDeletes.count
        blockedAuthors = state.blocked
    }

    /// Rebuilds the derived values, trims the cache and writes the snapshot.
    private func commit() {
        if state.known.count > Self.cacheLimit {
            let queued = Set(state.pending)
            let newest = state.known
                .sorted { $0.date > $1.date }
                .prefix(Self.cacheLimit)
            let keep = Set(newest.map(\.id)).union(queued)
            state.known = state.known.filter { keep.contains($0.id) }
        }
        let cutoff = clock().addingTimeInterval(-Self.rateLimit)
        state.lastSubmitted = state.lastSubmitted.filter { $0.value > cutoff }
        rebuild()
        persistence.save(state)
    }
}
