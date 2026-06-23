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

        let jobSource = (try? Data(contentsOf: folder.appendingPathComponent("job.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            .flatMap { $0["source"] as? String } ?? "live"

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
            syncState: "local",
            pipelineError: nil,   // a successful (re-)index clears any prior failure
            source: jobSource,
            calendarEventId: metadata.meeting.calendarEventId
        )
        try dbQueue.write { db in try record.save(db) }
        return record
    }

    /// Record a pipeline failure so the dashboard can show it (reliability pass). A failed job leaves no
    /// metadata.json, so `indexPackage` can't run; instead we read the record-time facts back from the
    /// `job.json` we wrote on Stop and upsert a minimal `status:"failed"` row carrying `error`. Idempotent
    /// (keyed on the meeting-id folder name); a later successful `indexPackage` overwrites it to
    /// `"transcribed"` with `pipelineError = nil`.
    @discardableResult
    public func markFailed(folder: URL, error: String?) throws -> MeetingRecord {
        let id = folder.lastPathComponent
        let job = (try? Data(contentsOf: folder.appendingPathComponent("job.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let nowISO = ISO8601DateFormatter().string(from: Date())
        let started = job["started_at"] as? String ?? nowISO
        let ended = job["ended_at"] as? String ?? nowISO
        let type = (job["profile"] as? String) == CaptureProfile.inPerson.rawValue ? "in_person" : "call"

        let existing = try meeting(id: id)
        let record = MeetingRecord(
            id: id,
            company: existing?.company,
            title: existing?.title,
            type: existing?.type ?? type,
            startedAt: existing?.startedAt ?? started,
            endedAt: existing?.endedAt ?? ended,
            durationSeconds: existing?.durationSeconds,
            status: "failed",
            speakerCount: existing?.speakerCount ?? 0,
            diarized: existing?.diarized ?? false,
            biased: existing?.biased ?? false,
            modelRevision: existing?.modelRevision,
            captureSourceApp: existing?.captureSourceApp ?? (job["capture_source_app"] as? String),
            folderPath: folder.path,
            consentStatus: existing?.consentStatus,
            driveFolderId: existing?.driveFolderId,
            syncState: existing?.syncState ?? "local",
            pipelineError: error ?? "Transcription failed (see pipeline.log).",
            source: (job["source"] as? String) ?? existing?.source ?? "live",
            calendarEventId: existing?.calendarEventId
        )
        try dbQueue.write { db in try record.save(db) }
        return record
    }

    /// Insert a lightweight `"processing"` row the moment a job starts, so the meeting shows in the
    /// dashboard (with a spinner) immediately instead of only appearing when the pipeline finishes. Reads
    /// the record-time facts from `job.json`. Non-destructive + idempotent: a real `"transcribed"`/
    /// `"failed"` row is left untouched (so a re-run never hides a finished or failed meeting).
    @discardableResult
    public func markProcessing(folder: URL) throws -> MeetingRecord? {
        let id = folder.lastPathComponent
        if let existing = try meeting(id: id), existing.status == "transcribed" || existing.status == "failed" {
            return existing
        }
        let job = (try? Data(contentsOf: folder.appendingPathComponent("job.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let nowISO = ISO8601DateFormatter().string(from: Date())
        let type = (job["profile"] as? String) == CaptureProfile.inPerson.rawValue ? "in_person" : "call"
        let record = MeetingRecord(
            id: id, company: nil, title: nil, type: type,
            startedAt: job["started_at"] as? String ?? nowISO,
            endedAt: job["ended_at"] as? String ?? nowISO,
            durationSeconds: nil, status: "processing", speakerCount: 0,
            diarized: false, biased: false, modelRevision: nil,
            captureSourceApp: job["capture_source_app"] as? String,
            folderPath: folder.path, consentStatus: nil, driveFolderId: nil,
            syncState: "local", pipelineError: nil,
            source: (job["source"] as? String) ?? "live", calendarEventId: nil)
        try dbQueue.write { db in try record.save(db) }
        return record
    }

    /// Reconcile the index with what's on disk — called on launch. Indexes any completed package whose
    /// completion the live `JobBridge` watcher missed (e.g. the app was relaunched mid-transcription, which
    /// otherwise leaves a finished meeting invisible forever), and surfaces a not-yet-started job as
    /// `"processing"`. Best-effort per folder; the on-disk package is the source of truth.
    public func reconcile(recordingsRoot: URL = RecordingsStore.root) {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(
            at: recordingsRoot, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for folder in folders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let hasMetadata = fm.fileExists(atPath: folder.appendingPathComponent("metadata.json").path)
            let hasJob = fm.fileExists(atPath: folder.appendingPathComponent("job.json").path)
            let existing = try? meeting(id: folder.lastPathComponent)
            if hasMetadata {
                if existing?.status != "transcribed" { _ = try? indexPackage(at: folder) }
            } else if hasJob, existing == nil {
                _ = try? markProcessing(folder: folder)
            }
        }
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

    /// Set the saventa-summary run state ("running" / "done" / "failed") with an optional error and the
    /// `claude -p` session id. `SummaryRunner` calls this; the dashboard observes the resulting row. The
    /// session id is preserved (COALESCE) when a later transition passes nil, so a "running" → "done" pair
    /// keeps whatever id was captured.
    public func updateSummaryState(id: String, state: String?, error: String? = nil,
                                   sessionId: String? = nil) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE meeting SET summaryState = ?, summaryError = ?, \
                summarySessionId = COALESCE(?, summarySessionId) WHERE id = ?
                """,
                arguments: [state, error, sessionId, id])
        }
    }

    /// The set of calendar event ids that already have a recording (any source). Powers the panel's
    /// "✓ recorded" marker. Distinct, non-null only.
    public func calendarEventIdsWithRecording() throws -> Set<String> {
        try dbQueue.read { db in
            Set(try String.fetchAll(db,
                sql: "SELECT DISTINCT calendarEventId FROM meeting WHERE calendarEventId IS NOT NULL"))
        }
    }

    /// The most recent meeting bound to a calendar event, if any (click-through from the panel).
    public func meeting(forCalendarEventId eventId: String) throws -> MeetingRecord? {
        try dbQueue.read { db in
            try MeetingRecord.filter(Column("calendarEventId") == eventId)
                .order(Column("startedAt").desc).fetchOne(db)
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
        migrator.registerMigration("v2-pipeline-error") { db in
            // Surface pipeline failures in the dashboard: a `status:"failed"` row carries the error here
            // (a failed job never produces a metadata.json, so `indexPackage` can't run — `markFailed`
            // writes a minimal row instead). Nullable; cleared when a later run succeeds.
            try db.alter(table: MeetingRecord.databaseTableName) { t in
                t.add(column: "pipelineError", .text)
            }
        }
        migrator.registerMigration("v3-summary-state") { db in
            // The post-meeting Claude summary (saventa-summary auto-trigger). `SummaryRunner` sets these;
            // the dashboard reads them. All nullable — a meeting with no summary leaves them nil.
            try db.alter(table: MeetingRecord.databaseTableName) { t in
                t.add(column: "summaryState", .text)       // "running" | "done" | "failed"
                t.add(column: "summaryError", .text)        // set only when summaryState == "failed"
                t.add(column: "summarySessionId", .text)    // claude -p session id, for a later --resume
            }
        }
        migrator.registerMigration("v4-import-source") { db in
            // Provenance of an imported recording vs a live capture, and the calendar event it's bound to
            // (the latter also backfills live captures that matched an event, so the calendar panel can
            // mark events "✓ recorded"). `source` is NOT NULL with a "live" default so existing rows are
            // unambiguous; `calendarEventId` is nullable (no-event imports + unmatched live captures).
            try db.alter(table: MeetingRecord.databaseTableName) { t in
                t.add(column: "source", .text).notNull().defaults(to: "live")
                t.add(column: "calendarEventId", .text)
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
    /// Non-nil only when `status == "failed"`: the pipeline error to show in the dashboard.
    public var pipelineError: String?
    /// The saventa-summary auto-trigger state: "running" | "done" | "failed" (nil = never run). Defaulted
    /// so the existing `MeetingRecord(...)` call sites (index / markFailed) compile unchanged.
    public var summaryState: String? = nil
    /// Set only when `summaryState == "failed"`: the summary error to show in the dashboard.
    public var summaryError: String? = nil
    /// The `claude -p` session id from the summary run, so a later "ask a follow-up" can `--resume`.
    public var summarySessionId: String? = nil
    /// "live" (default) | "imported" — provenance, surfaced as the dashboard "Imported" badge.
    public var source: String = "live"
    /// The Google Calendar event id this meeting is bound to (nil = none). Lets the calendar panel mark
    /// events as already recorded and open them. Filled from `metadata.meeting.calendarEventId` at index.
    public var calendarEventId: String? = nil
}
