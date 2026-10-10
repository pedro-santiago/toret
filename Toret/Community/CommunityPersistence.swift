import Foundation

/// Everything the community feature remembers between launches.
///
/// Kept in one file so it is read and written as one consistent snapshot. None
/// of it is a secret and none of it is the user's identity: reports (their own
/// and the ones they last downloaded), what is still waiting to be uploaded, and
/// what they chose to hide.
struct CommunityState: Codable, Equatable, Sendable {
    /// Every report on screen: downloaded ones and this device's own.
    var known: [Report] = []
    /// Ids of reports written here and not yet uploaded.
    var pending: [String] = []
    /// Ids of reports deleted here whose deletion is not yet uploaded.
    var pendingDeletes: [String] = []
    /// Complaints not yet uploaded.
    var pendingFlags: [PendingFlag] = []
    /// Reports the user reported or hid. Hidden from this device straight away.
    var hidden: [String] = []
    /// Authors the user blocked.
    var blocked: [String] = []
    /// When this device last reported on each fountain, for the rate limit.
    var lastSubmitted: [String: Date] = [:]
    /// Random, per install. The author handle until an iCloud account is known.
    var installID: String = UUID().uuidString
    /// The hashed-handle seed of the iCloud account, once seen, so the handle is
    /// the same offline.
    var accountToken: String?

    struct PendingFlag: Codable, Equatable, Sendable {
        let reportID: String
        let reason: String
    }
}

protocol CommunityPersistence: Sendable {
    func load() -> CommunityState?
    func save(_ state: CommunityState)
}

/// A JSON file in Application Support. Written whole and atomically; a few
/// hundred short reports is far too small to be worth anything cleverer.
struct FilePersistence: CommunityPersistence {
    let url: URL

    init(url: URL = FilePersistence.defaultURL("community-state.json")) {
        self.url = url
    }

    static func defaultURL(_ name: String) -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Toret", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }

    func load() -> CommunityState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(CommunityState.self, from: data)
    }

    func save(_ state: CommunityState) {
        guard let data = try? Self.encoder.encode(state) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
