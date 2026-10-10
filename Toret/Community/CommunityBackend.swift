import CryptoKit
import Foundation

/// Whether reports can be shared with other people right now, and if not, why.
enum CommunityAvailability: Equatable, Sendable {
    /// This build has no shared database; reports stay on the device.
    case localOnly
    /// Signed in to iCloud and able to write to the public database.
    case ready
    /// Reading works without an account; writing needs one.
    case signedOut
    /// Screen Time or a profile forbids iCloud.
    case restricted
    /// iCloud could not be reached or has not answered yet.
    case unavailable
}

/// Where reports live.
///
/// Everything the community feature does to the outside world goes through this
/// one seam, so the real database (CloudKit) can be swapped for a file on the
/// device — in a Debug build, in a test, or when the user has no iCloud at all —
/// without the rest of the app noticing.
protocol CommunityBackend: Sendable {
    /// Whether what is saved here is visible to other people.
    var isShared: Bool { get }

    func availability() async -> CommunityAvailability

    /// An opaque, stable identifier for the signed-in account, hashed into the
    /// author's handle and never shown or sent as it is. Nil when there is none.
    func accountToken() async -> String?

    /// The newest reports across the city, newest first.
    func recent(limit: Int) async throws -> [Report]

    /// The newest reports about one fountain, newest first.
    func reports(for fountainID: String, limit: Int) async throws -> [Report]

    /// Saves a report. Saving the same report twice must be harmless: an upload
    /// that timed out is retried, and the first attempt may have landed.
    func save(_ report: Report) async throws

    /// Deletes a report. Deleting one that is already gone must be harmless.
    func delete(reportID: String) async throws

    /// Tells the owner a report is objectionable.
    func flag(reportID: String, reason: String) async throws
}

enum CommunityError: Error, Equatable {
    /// Writing needs an iCloud account and there is none.
    case notSignedIn
    /// The backend cannot be reached or is not configured.
    case unavailable
}

/// The anonymous name a report goes out under: "Visitante 4F2A91".
///
/// Derived by hashing an opaque identifier, so the same person is recognisable
/// to the people who block them and to nobody else. Six hex digits keep two
/// strangers from sharing a handle, which matters because blocking is by handle.
enum AuthorHandle {
    static func make(from token: String) -> String {
        let digest = SHA256.hash(data: Data("toret.author.\(token)".utf8))
        let hex = digest.prefix(3).map { String(format: "%02X", $0) }.joined()
        return "Visitante \(hex)"
    }
}
