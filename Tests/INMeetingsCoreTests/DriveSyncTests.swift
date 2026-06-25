import XCTest
@testable import INMeetingsCore

/// Records the folder/upload calls so we can assert the company-first layout, the text-vs-resumable
/// routing, and idempotency — all without real HTTP.
private final class FakeUploader: DriveUploading, @unchecked Sendable {
    var folderRequests: [String] = []
    var uploadedNames: [String] = []      // one-shot (text)
    var resumableUploads: [String] = []   // streamed (recordings)
    var replacedNames: [String] = []      // upload-or-replace (summary.md re-upload)

    func findOrCreateFolder(name: String, parentID: String, driveId: String?) async throws -> String {
        folderRequests.append(name)
        return "folder:\(name)"
    }

    func uploadFile(name: String, mimeType: String, data: Data, parentID: String, driveId: String?) async throws -> String {
        uploadedNames.append(name)
        return "file:\(name)"
    }

    func uploadFileResumable(name: String, mimeType: String, fileURL: URL, parentID: String, driveId: String?) async throws -> String {
        resumableUploads.append(name)
        return "file:\(name)"
    }

    func uploadOrReplaceFile(name: String, mimeType: String, data: Data, parentID: String, driveId: String?) async throws -> String {
        replacedNames.append(name)
        return "replaced-\(name)"
    }
}

final class DriveSyncTests: XCTestCase {
    private var goldenFixture: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "schema/fixtures/golden-package")
    }

    private let location = DriveLocation(driveID: "0ASHAREDDRIVE", folderID: "BASE", displayName: "Test")

    func testCompanyFolderNameFallsBackToUnmatched() throws {
        let m = try PackageReader.metadata(in: goldenFixture)
        XCTAssertEqual(DriveSync.companyFolderName(m), "Prelligence")
    }

    func testSyncBuildsCompanyFirstLayoutAndUploadsTextPackage() async throws {
        let store = try MeetingStore()
        let record = try store.indexPackage(at: goldenFixture)
        let fake = FakeUploader()
        let sync = DriveSync(client: fake, store: store)

        let result = try await sync.sync(meetingID: record.id, packageFolder: goldenFixture, into: location)

        XCTAssertEqual(fake.folderRequests, ["Prelligence", record.id])          // company, then meeting
        XCTAssertEqual(Set(fake.uploadedNames), ["metadata.json", "transcript.json", "transcript.txt", "context.md"])
        XCTAssertTrue(fake.resumableUploads.isEmpty)                             // the fixture has no recordings
        XCTAssertEqual(result.meetingFolderID, "folder:\(record.id)")

        let updated = try store.meeting(id: record.id)
        XCTAssertEqual(updated?.syncState, "synced")
    }

    func testSyncUploadsRecordingsViaResumable() async throws {
        let store = try MeetingStore()
        let fake = FakeUploader()
        let sync = DriveSync(client: fake, store: store)

        // A package folder: the text files (from the fixture) + dummy recordings.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pkg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["metadata.json", "transcript.json", "transcript.txt", "context.md"] {
            try FileManager.default.copyItem(at: goldenFixture.appendingPathComponent(name),
                                             to: dir.appendingPathComponent(name))
        }
        try Data("RIFFmic".utf8).write(to: dir.appendingPathComponent("mic.wav"))
        try Data("RIFFsys".utf8).write(to: dir.appendingPathComponent("system.wav"))

        let record = try store.indexPackage(at: dir)
        _ = try await sync.sync(meetingID: record.id, packageFolder: dir, into: location)

        XCTAssertEqual(Set(fake.resumableUploads), ["mic.wav", "system.wav"])    // recordings → resumable
        XCTAssertTrue(fake.uploadedNames.contains("transcript.txt"))            // readable transcript → one-shot
        XCTAssertTrue(fake.uploadedNames.contains("metadata.json"))
    }

    func testMediaSelectionPrefersMergedFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("a".utf8).write(to: dir.appendingPathComponent("mic.wav"))
        try Data("b".utf8).write(to: dir.appendingPathComponent("system.wav"))
        XCTAssertEqual(DriveSync.mediaFileNames(in: dir), ["mic.wav", "system.wav"])   // no merged yet
        try Data("c".utf8).write(to: dir.appendingPathComponent("audio.m4a"))
        XCTAssertEqual(DriveSync.mediaFileNames(in: dir), ["audio.m4a"])               // prefer mixed audio
        try Data("d".utf8).write(to: dir.appendingPathComponent("meeting.mp4"))
        XCTAssertEqual(DriveSync.mediaFileNames(in: dir), ["meeting.mp4"])             // video call: muxed file wins
    }

    func testMediaSelectionFallsBackToRawTracksPlusVideo() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("a".utf8).write(to: dir.appendingPathComponent("mic.wav"))
        try Data("v".utf8).write(to: dir.appendingPathComponent("video.mov"))
        // mux hasn't run (no meeting.mp4/audio.m4a): upload the raw tracks + raw video so nothing is lost
        XCTAssertEqual(DriveSync.mediaFileNames(in: dir), ["mic.wav", "video.mov"])
    }

    func testPrunesRawTracksAfterBackupWhenMergedExists() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let defaults = UserDefaults(suiteName: "prune-\(UUID().uuidString)")!
        for n in ["mic.wav", "system.wav", "video.mov", "meeting.mp4"] {
            try Data("x".utf8).write(to: dir.appendingPathComponent(n))
        }
        DriveSync.pruneRawTracksIfEnabled(in: dir, defaults: defaults)   // default ON
        let fm = FileManager.default
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("mic.wav").path))
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("system.wav").path))
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("video.mov").path))
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("meeting.mp4").path))   // merged kept
    }

    func testPruneIsNoOpWithoutAMergedFileOrWhenDisabled() throws {
        let fm = FileManager.default
        func freshDir() throws -> URL {
            let d = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: d.appendingPathComponent("mic.wav"))
            return d
        }
        // No merged file → never prune (don't leave the user with nothing to play).
        let noMerged = try freshDir(); defer { try? fm.removeItem(at: noMerged) }
        DriveSync.pruneRawTracksIfEnabled(in: noMerged, defaults: UserDefaults(suiteName: "p1-\(UUID().uuidString)")!)
        XCTAssertTrue(fm.fileExists(atPath: noMerged.appendingPathComponent("mic.wav").path))

        // Setting off → keep raw tracks even with a merged file present.
        let disabled = try freshDir(); defer { try? fm.removeItem(at: disabled) }
        try Data("m".utf8).write(to: disabled.appendingPathComponent("audio.m4a"))
        let off = UserDefaults(suiteName: "p2-\(UUID().uuidString)")!
        off.set(false, forKey: CaptureSettings.Keys.pruneRawTracksAfterBackup)
        DriveSync.pruneRawTracksIfEnabled(in: disabled, defaults: off)
        XCTAssertTrue(fm.fileExists(atPath: disabled.appendingPathComponent("mic.wav").path))
    }

    func testSyncSummaryReuploadsOnlySummaryToExistingFolder() async throws {
        let store = try MeetingStore()
        let fake = FakeUploader()
        let sync = DriveSync(client: fake, store: store)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sum-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.copyItem(at: goldenFixture.appendingPathComponent("metadata.json"),
                                         to: dir.appendingPathComponent("metadata.json"))
        let record = try store.indexPackage(at: dir)
        try "**Team**\n>X".write(to: dir.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)

        // Never synced yet (no driveFolderId) → no-op.
        let early = try await sync.syncSummary(meetingID: record.id, packageFolder: dir, into: location)
        XCTAssertFalse(early)
        XCTAssertTrue(fake.replacedNames.isEmpty)

        // Once the package is synced (folder id set), re-upload only summary.md via upload-or-replace.
        try store.setSyncState(id: record.id, driveFolderId: "folder:meeting", syncState: "synced")
        let ok = try await sync.syncSummary(meetingID: record.id, packageFolder: dir, into: location)
        XCTAssertTrue(ok)
        XCTAssertEqual(fake.replacedNames, ["summary.md"])
        XCTAssertTrue(fake.uploadedNames.isEmpty)            // no full re-sync, just the one file
    }

    func testSyncSummaryUploadsNamedPerRecipeFileFlattened() async throws {
        // The generalized `syncSummary(fileName:)` uploads any named summary file (per-recipe support).
        // A `summaries/<recipeId>.md` subpath is flattened to `<recipeId>.md` in the meeting's Drive folder.
        let store = try MeetingStore()
        let fake = FakeUploader()
        let sync = DriveSync(client: fake, store: store)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("perrecipe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.copyItem(at: goldenFixture.appendingPathComponent("metadata.json"),
                                         to: dir.appendingPathComponent("metadata.json"))
        let record = try store.indexPackage(at: dir)
        let summariesDir = dir.appendingPathComponent("summaries")
        try FileManager.default.createDirectory(at: summariesDir, withIntermediateDirectories: true)
        try "# short brief".write(to: summariesDir.appendingPathComponent("short-brief.md"),
                                  atomically: true, encoding: .utf8)
        try store.setSyncState(id: record.id, driveFolderId: "folder:meeting", syncState: "synced")

        let ok = try await sync.syncSummary(meetingID: record.id, packageFolder: dir,
                                            fileName: "summaries/short-brief.md", into: location)
        XCTAssertTrue(ok)
        XCTAssertEqual(fake.replacedNames, ["short-brief.md"])   // subpath flattened to the leaf name
    }

    func testSyncSummaryDefaultsToSummaryMarkdown() async throws {
        // The default `fileName` is "summary.md" — back-compat with the existing single-summary callers.
        let store = try MeetingStore()
        let fake = FakeUploader()
        let sync = DriveSync(client: fake, store: store)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("default-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.copyItem(at: goldenFixture.appendingPathComponent("metadata.json"),
                                         to: dir.appendingPathComponent("metadata.json"))
        let record = try store.indexPackage(at: dir)
        try "**Team**".write(to: dir.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)
        try store.setSyncState(id: record.id, driveFolderId: "folder:meeting", syncState: "synced")

        let ok = try await sync.syncSummary(meetingID: record.id, packageFolder: dir, into: location)
        XCTAssertTrue(ok)
        XCTAssertEqual(fake.replacedNames, ["summary.md"])       // default leaf name
    }

    func testSyncIsIdempotentOnceSynced() async throws {
        let store = try MeetingStore()
        let record = try store.indexPackage(at: goldenFixture)
        let fake = FakeUploader()
        let sync = DriveSync(client: fake, store: store)

        _ = try await sync.sync(meetingID: record.id, packageFolder: goldenFixture, into: location)
        let uploadsAfterFirst = fake.uploadedNames.count

        let second = try await sync.sync(meetingID: record.id, packageFolder: goldenFixture, into: location)
        XCTAssertTrue(second.uploaded.isEmpty)
        XCTAssertEqual(fake.uploadedNames.count, uploadsAfterFirst)
    }
}
