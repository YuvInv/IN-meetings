import Foundation
import GRDB

/// The local SQLite index over every meeting (ADR-006): a fast, queryable mirror of the per-meeting
/// context packages that powers the dashboard (ADR-007) and tracks Drive sync state (slice 6).
///
/// Local disk is a cache; Drive is the durable source of truth. The DB lives next to the model cache
/// under `~/Library/Application Support/IN Meetings/`. FTS5 search is deferred to the dashboard (H4).
public final class MeetingStore {
    private let dbQueue: DatabaseQueue

    /// Open (creating if needed) the on-disk index at `url`.
    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        dbQueue = try DatabaseQueue(path: url.path)
        try Self.migrator.migrate(dbQueue)
    }

    /// In-memory index — used by tests.
    public init() throws {
        dbQueue = try DatabaseQueue()
        try Self.migrator.migrate(dbQueue)
    }

    /// `~/Library/Application Support/IN Meetings/meetings.db` (sibling of the model cache).
    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("IN Meetings/meetings.db")
    }

    // MARK: - Indexing

    /// Read a finished context-package folder (ADR-005) and upsert its row. Idempotent: re-indexing the
    /// same meeting updates the row in place. The folder's name is the meeting id (the local key).
    @discardableResult
    public func indexPackage(at folder: URL) throws -> MeetingRecord {
        let metadata = try PackageReader.metadata(in: folder)
        let transcript = try? PackageReader.transcript(in: folder)

        let durations = metadata.recording.durations
        let duration = durations?["mic"] ?? durations?.values.max()

        let record = MeetingRecord(
            id: folder.lastPathComponent,
            company: metadata.company?.name,
            title: metadata.meeting.title,
            type: metadata.meeting.type,
            startedAt: metadata.meeting.start,
            endedAt: metadata.meeting.end,
            durationSeconds: duration,
            status: "transcribed",
            speakerCount: transcript?.speakers.count ?? 0,
            diarized: transcript?.diarized ?? false,
            biased: metadata.transcription.biased,
            modelRevision: metadata.transcription.modelRevision,
            captureSourceApp: metadata.recording.captureSourceApp,
            folderPath: folder.path,
            consentStatus: metadata.consent?.status,
            driveFolderId: nil,   // set by slice 6 (Drive sync) via a dedicated update path
            syncState: "local"
        )
        try dbQueue.write { db in try record.save(db) }
        return record
    }

    // MARK: - Queries

    /// Every meeting, most recent first (the dashboard list, ADR-007).
    public func allMeetings() throws -> [MeetingRecord] {
        try dbQueue.read { db in
            try MeetingRecord.order(Column("startedAt").desc).fetchAll(db)
        }
    }

    public func meeting(id: String) throws -> MeetingRecord? {
        try dbQueue.read { db in try MeetingRecord.fetchOne(db, key: id) }
    }

    /// Record the Drive destination + sync state after an upload (slice 6).
    public func setSyncState(id: String, driveFolderId: String?, syncState: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE meeting SET driveFolderId = ?, syncState = ? WHERE id = ?",
                arguments: [driveFolderId, syncState, id])
        }
    }

    /// Set or clear (`name == nil`) the company for a meeting — the manual dashboard fix (P1).
    public func updateCompany(id: String, name: String?) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE meeting SET company = ? WHERE id = ?", arguments: [name, id])
        }
    }

    // MARK: - Schema

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-meetings") { db in
            try db.create(table: MeetingRecord.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("company", .text)
                t.column("title", .text)
                t.column("type", .text).notNull()
                t.column("startedAt", .text).notNull()
                t.column("endedAt", .text).notNull()
                t.column("durationSeconds", .double)
                t.column("status", .text).notNull()
                t.column("speakerCount", .integer).notNull()
                t.column("diarized", .boolean).notNull()
                t.column("biased", .boolean).notNull()
                t.column("modelRevision", .text)
                t.column("captureSourceApp", .text)
                t.column("folderPath", .text).notNull()
                t.column("consentStatus", .text)
                t.column("driveFolderId", .text)
                t.column("syncState", .text).notNull()
            }
        }
        return migrator
    }
}

/// One indexed meeting (ADR-006). A GRDB record mapped to the `meeting` table; Drive ids + sync state
/// are filled by slice 6, skill-run results by Phase 3.
public struct MeetingRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "meeting"

    public var id: String
    public var company: String?
    public var title: String?
    public var type: String
    public var startedAt: String
    public var endedAt: String
    public var durationSeconds: Double?
    public var status: String
    public var speakerCount: Int
    public var diarized: Bool
    public var biased: Bool
    public var modelRevision: String?
    public var captureSourceApp: String?
    public var folderPath: String
    public var consentStatus: String?
    public var driveFolderId: String?
    public var syncState: String
}
