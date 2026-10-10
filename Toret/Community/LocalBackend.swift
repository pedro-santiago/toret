import Foundation

/// A community of one: reports are kept in a file on the device.
///
/// Used when this build has no shared database — a Debug build, a Personal-team
/// install — so every screen of the feature still works and can be tried.
/// Nothing saved here ever reaches anyone else, and the UI says so.
actor LocalBackend: CommunityBackend {
    nonisolated let isShared = false
    private let url: URL

    init(url: URL = FilePersistence.defaultURL("community-local.json")) {
        self.url = url
    }

    func availability() async -> CommunityAvailability { .localOnly }

    func accountToken() async -> String? { nil }

    func recent(limit: Int) async throws -> [Report] {
        Array(load().sorted { $0.date > $1.date }.prefix(limit))
    }

    func reports(for fountainID: String, limit: Int) async throws -> [Report] {
        Array(load().filter { $0.fountainID == fountainID }.sorted { $0.date > $1.date }.prefix(limit))
    }

    func save(_ report: Report) async throws {
        var all = load().filter { $0.id != report.id }
        all.append(report)
        store(all)
    }

    func delete(reportID: String) async throws {
        store(load().filter { $0.id != reportID })
    }

    func flag(reportID: String, reason: String) async throws {
        // Nobody else will read it; the report is already hidden on this device.
    }

    private func load() -> [Report] {
        guard let data = try? Data(contentsOf: url),
              let reports = try? FilePersistence.decoder.decode([Report].self, from: data)
        else { return [] }
        return reports
    }

    private func store(_ reports: [Report]) {
        guard let data = try? FilePersistence.encoder.encode(reports) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
