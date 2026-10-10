import CloudKit
import Foundation

/// The shared community: CloudKit's public database, which costs nothing and
/// needs no server of ours.
///
/// Anyone can read it; writing needs an iCloud account, and CloudKit rather than
/// the app enforces that a report can only be changed or deleted by its creator.
/// Records carry the fountain, the state, the rating, the tags, the note, the
/// date and the anonymous handle — no name, no email, no position.
///
/// Never constructed unless the app was built with the iCloud entitlement:
/// creating a `CKContainer` without one crashes rather than failing, so the
/// container id comes from an Info.plist key that is empty everywhere else.
final class CloudKitBackend: CommunityBackend, @unchecked Sendable {
    let isShared = true

    /// `CKContainer` and `CKDatabase` are documented as safe to use from any
    /// thread; they are stored once and never mutated, which is the whole case
    /// for the `@unchecked`.
    private let container: CKContainer
    private var database: CKDatabase { container.publicCloudDatabase }

    private enum RecordType {
        static let report = "Report"
        static let flag = "Flag"
    }

    /// How far back "recent" reaches. A month of fountain news is plenty, and a
    /// bounded window keeps the query on its index.
    private static let window: TimeInterval = 30 * 86400

    init(containerIdentifier: String) {
        container = CKContainer(identifier: containerIdentifier)
    }

    func availability() async -> CommunityAvailability {
        do {
            switch try await container.accountStatus() {
            case .available: return .ready
            case .noAccount: return .signedOut
            case .restricted: return .restricted
            case .couldNotDetermine, .temporarilyUnavailable: return .unavailable
            @unknown default: return .unavailable
            }
        } catch {
            return .unavailable
        }
    }

    func accountToken() async -> String? {
        try? await container.userRecordID().recordName
    }

    func recent(limit: Int) async throws -> [Report] {
        let cutoff = Date().addingTimeInterval(-Self.window) as NSDate
        let query = CKQuery(recordType: RecordType.report, predicate: NSPredicate(format: "date > %@", cutoff))
        query.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return try await run(query, limit: limit)
    }

    func reports(for fountainID: String, limit: Int) async throws -> [Report] {
        let query = CKQuery(
            recordType: RecordType.report,
            predicate: NSPredicate(format: "fountainID == %@", fountainID)
        )
        query.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return try await run(query, limit: limit)
    }

    func save(_ report: Report) async throws {
        let record = CKRecord(
            recordType: RecordType.report,
            recordID: CKRecord.ID(recordName: report.id)
        )
        record["fountainID"] = report.fountainID as CKRecordValue
        record["state"] = report.state.rawValue as CKRecordValue
        record["rating"] = (report.rating ?? 0) as CKRecordValue
        record["tags"] = report.tags.map(\.rawValue) as CKRecordValue
        record["note"] = report.note as CKRecordValue
        record["date"] = report.date as CKRecordValue
        record["author"] = report.author as CKRecordValue
        do {
            _ = try await database.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            // The same report, uploaded by an earlier attempt that timed out.
        } catch let error as CKError where error.code == .notAuthenticated {
            throw CommunityError.notSignedIn
        }
    }

    func delete(reportID: String) async throws {
        do {
            try await database.deleteRecord(withID: CKRecord.ID(recordName: reportID))
        } catch let error as CKError where error.code == .unknownItem {
            // Already gone.
        }
    }

    func flag(reportID: String, reason: String) async throws {
        let record = CKRecord(recordType: RecordType.flag)
        record["reportID"] = reportID as CKRecordValue
        record["reason"] = reason as CKRecordValue
        record["date"] = Date() as CKRecordValue
        do {
            _ = try await database.save(record)
        } catch let error as CKError where error.code == .notAuthenticated {
            throw CommunityError.notSignedIn
        }
    }

    // MARK: Reading

    private func run(_ query: CKQuery, limit: Int) async throws -> [Report] {
        let (matches, _) = try await database.records(matching: query, resultsLimit: limit)
        return matches.compactMap { _, result in
            (try? result.get()).flatMap(Self.report(from:))
        }
    }

    /// Anything in the public database is untrusted: a record that is missing a
    /// field, or carries an unknown state, is dropped, and `Report.init` clamps
    /// the rating and the note to what the app would have accepted.
    private static func report(from record: CKRecord) -> Report? {
        guard record.recordType == RecordType.report,
              let fountainID = record["fountainID"] as? String,
              let rawState = record["state"] as? String,
              let state = WaterState(rawValue: rawState),
              let date = record["date"] as? Date
        else { return nil }

        let rating = (record["rating"] as? Int).flatMap { $0 > 0 ? $0 : nil }
        let tags = Array(
            (record["tags"] as? [String] ?? []).compactMap(ReportTag.init(rawValue:)).prefix(3)
        )
        return Report(
            id: record.recordID.recordName,
            fountainID: fountainID,
            state: state,
            rating: rating,
            tags: tags,
            note: record["note"] as? String ?? "",
            date: date,
            author: record["author"] as? String ?? "Visitante",
            isMine: false
        )
    }
}
