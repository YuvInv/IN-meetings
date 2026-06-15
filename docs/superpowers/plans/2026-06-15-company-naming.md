# Company naming + edit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Catch more company names automatically (calendar domain + a conservative title fallback) and let the user set/rename a meeting's company from the dashboard, persisting to the local index, the meeting's `metadata.json`, and (when synced) its Drive copy.

**Architecture:** Python adds a title fallback to `resolve_company` + a `company.source` provenance field. Swift gains `MeetingStore.updateCompany`, a Core `CompanyEditor` (single-field `metadata.json` rewrite + SQLite), an inline-editable company field in the detail view via `RecordingStore.setCompany`, and a Drive re-upload primitive (`DriveClient.uploadOrReplaceFile`) wired through `DriveAuth`.

**Tech Stack:** Python 3.11 (pytest, run from `pipeline/.venv`), Swift/SwiftUI (XCTest, GRDB), Google Drive v3. Spec: `docs/superpowers/specs/2026-06-15-company-naming-edit-design.md`. Branch: `feat/company-naming`.

**Verification note:** Tasks 1, 3, 4, and the client part of 6 have real unit tests. Tasks 5 and the wiring of 6 are SwiftUI/Drive integration with no app-target test bundle — verified by `make build-mac` **plus** a manual run (a clean build is necessary but not sufficient).

## File structure
- `pipeline/in_meetings_pipeline/context_assembler.py` — title fallback + `source` (Task 1).
- `pipeline/in_meetings_pipeline/metadata.py` — default `company.source = None` (Task 1).
- `pipeline/tests/test_context.py` — title-fallback tests (Task 1).
- `schema/metadata.schema.json` + `schema/fixtures/golden-package/metadata.json` — `company.source` (Task 2).
- `Sources/INMeetingsCore/Store/ContextPackage.swift` — `Company.source` (Task 3).
- `Sources/INMeetingsCore/Store/MeetingStore.swift` — `updateCompany` (Task 3).
- **new** `Sources/INMeetingsCore/Store/CompanyEditor.swift` (Task 4).
- **new** `Tests/INMeetingsCoreTests/CompanyEditorTests.swift` (Task 4); `MeetingStoreTests.swift` (Task 3).
- `Apps/INMeetings/INMeetings/Dashboard/MeetingDetailView.swift` + `RecordingStore.swift` (Task 5).
- `Sources/INMeetingsCore/Drive/DriveClient.swift` (+ `DriveSync.swift` protocol) + `DriveAuth.swift` + `DashboardWindow.swift` (Task 6); `DriveClientTests.swift` + `DriveSyncTests.swift` fake (Task 6).

---

### Task 1: Title fallback + `source` (Python inference)

**Files:**
- Modify: `pipeline/in_meetings_pipeline/context_assembler.py` (`resolve_company` ~127-138; add helpers above it)
- Modify: `pipeline/in_meetings_pipeline/metadata.py:82-85`
- Test: `pipeline/tests/test_context.py`

- [ ] **Step 1: Write the failing tests** — append to `pipeline/tests/test_context.py`:

```python
def test_resolve_company_title_fallback_meets_separator() -> None:
    # No external email domain → fall back to the title's external party.
    assert resolve_company([], "Prelligence <> IN Venture") == {
        "name": "Prelligence", "sevanta_deal_id": None, "dealigence_id": None,
        "matched": False, "source": "title"}


def test_resolve_company_title_fallback_intro_prefix() -> None:
    c = resolve_company([], "Intro with Acme AI")
    assert c["name"] == "Acme AI" and c["source"] == "title"


def test_resolve_company_title_fallback_slash() -> None:
    assert resolve_company([], "IN Venture / Acme")["name"] == "Acme"


def test_resolve_company_title_rejects_generic() -> None:
    assert resolve_company([], "Weekly sync") is None
    assert resolve_company([], "1:1") is None
    assert resolve_company([], "IN Venture") is None
    assert resolve_company([], None) is None


def test_resolve_company_domain_sets_source_domain() -> None:
    att = split_sides(_EVENT, "in-venture.com")
    assert resolve_company(att, _EVENT["summary"])["source"] == "domain"
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd pipeline && .venv/bin/python -m pytest tests/test_context.py -k "title_fallback or title_rejects or source_domain" -q`
Expected: FAIL (`KeyError: 'source'` / wrong None handling).

- [ ] **Step 3: Implement** — in `context_assembler.py`, ensure `import re` is present at the top (add if missing), then add these helpers immediately above `resolve_company` and rewrite `resolve_company`:

```python
_FUND_NAMES = {"in venture", "in-venture", "inventure", "inv", "in"}
_GENERIC_TITLE = {"weekly sync", "sync", "standup", "stand-up", "1:1", "catch up", "catch-up",
                  "team", "internal", "check-in", "checkin", "meeting", "call", "intro",
                  "introduction", "chat", "external"}
_TITLE_SEPARATORS = [" <> ", " <-> ", " >< ", " / ", " | ", " – ", " — ", " - ", " x "]
_INTRO_PREFIX = re.compile(
    r"^\s*(?:intro|introduction|call|meeting|sync|chat)\b.*?\b(?:with|to|for)\s+(.+)$", re.I)


def _internal_names(attendees: list[Attendee]) -> set[str]:
    names = set(_FUND_NAMES)
    for a in attendees:
        if a.side == "internal" and a.name:
            names.add(a.name.lower())
            names.add(a.name.split()[0].lower())
    return names


def _is_company_like(cand: str, internal: set[str]) -> bool:
    low = cand.lower()
    return len(cand) >= 2 and low not in _GENERIC_TITLE and low not in internal


def _company_from_title(title: str | None, internal: set[str]) -> str | None:
    if not title:
        return None
    raw = title.strip()
    for sep in _TITLE_SEPARATORS:
        if sep in raw:
            parts = [p.strip() for p in raw.split(sep) if p.strip()]
            external = [p for p in parts if p.lower() not in internal]
            if len(external) == 1 and _is_company_like(external[0], internal):
                return external[0]
            return None
    m = _INTRO_PREFIX.match(raw)
    if m and _is_company_like(m.group(1).strip(), internal):
        return m.group(1).strip()
    return None


def resolve_company(attendees: list[Attendee], title: str | None) -> dict | None:
    """Company = dominant external email domain; else a conservative title fallback; else None.
    matched is always False here (no CRM); source records how the name was found."""
    domains = [d for a in attendees if a.side == "external"
               if (d := _domain(a.email)) and d not in _PUBLIC_DOMAINS]
    if domains:
        dominant = Counter(domains).most_common(1)[0][0]
        return {"name": _company_name_from_domain(dominant), "sevanta_deal_id": None,
                "dealigence_id": None, "matched": False, "source": "domain"}
    name = _company_from_title(title, _internal_names(attendees))
    if name:
        return {"name": name, "sevanta_deal_id": None, "dealigence_id": None,
                "matched": False, "source": "title"}
    return None
```

- [ ] **Step 4: Default `source` in metadata.py** — change the `company` default (`metadata.py:82-85`):

```python
    company = (
        context.company if (context and context.company)
        else {"name": None, "sevanta_deal_id": None, "dealigence_id": None,
              "matched": False, "source": None}
    )
```

- [ ] **Step 5: Run the full context + metadata + contract suites**

Run: `cd pipeline && .venv/bin/python -m pytest tests/test_context.py tests/test_metadata.py tests/test_contract.py -q`
Expected: PASS (existing `test_resolve_company_*` still pass — they assert specific keys, not the absence of `source`).

- [ ] **Step 6: Lint + commit**

```bash
cd pipeline && uvx ruff check in_meetings_pipeline tests
cd /Users/yuvalnaor/repos/IN-meetings
git add pipeline/in_meetings_pipeline/context_assembler.py pipeline/in_meetings_pipeline/metadata.py pipeline/tests/test_context.py
git commit -m "feat(pipeline): company title-fallback inference + company.source provenance"
```

---

### Task 2: `company.source` in the schema + golden fixture

**Files:**
- Modify: `schema/metadata.schema.json:51-56` (company properties)
- Modify: `schema/fixtures/golden-package/metadata.json:14-19`

- [ ] **Step 1: Add `source` to the schema** — in the `company.properties` object, after the `dealigence_id` line, add:

```json
          "source": {
            "type": ["string", "null"],
            "description": "How the name was set: \"domain\" | \"title\" | \"user\". null when unset."
          },
```

(Leave `"required": ["matched"]` unchanged — `source` is optional.)

- [ ] **Step 2: Add `source` to the golden fixture** — in `company`, after the `dealigence_id` line:

```json
    "dealigence_id": "dlg_991",
    "source": "domain",
    "matched": true
```

- [ ] **Step 3: Verify the contract test still validates** (the pipeline output + fixture against the schema)

Run: `cd pipeline && .venv/bin/python -m pytest tests/test_contract.py -q`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add schema/metadata.schema.json schema/fixtures/golden-package/metadata.json
git commit -m "feat(schema): add optional company.source (additive, no version bump)"
```

---

### Task 3: `Company.source` (Swift model) + `MeetingStore.updateCompany`

**Files:**
- Modify: `Sources/INMeetingsCore/Store/ContextPackage.swift:64-69`
- Modify: `Sources/INMeetingsCore/Store/MeetingStore.swift` (add a method after `setSyncState`, ~line 88)
- Test: `Tests/INMeetingsCoreTests/MeetingStoreTests.swift`

- [ ] **Step 1: Write the failing test** — append to `MeetingStoreTests.swift` (inside the class):

```swift
    func testUpdateCompanyChangesAndClearsTheRow() throws {
        let store = try MeetingStore()
        let rec = try store.indexPackage(at: fixture)
        try store.updateCompany(id: rec.id, name: "Acme AI")
        XCTAssertEqual(try store.meeting(id: rec.id)?.company, "Acme AI")
        try store.updateCompany(id: rec.id, name: nil)
        XCTAssertNil(try store.meeting(id: rec.id)?.company)
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter MeetingStoreTests/testUpdateCompanyChangesAndClearsTheRow`
Expected: FAIL (no `updateCompany` member).

- [ ] **Step 3: Implement** — add to `MeetingStore` (after `setSyncState`):

```swift
    /// Set or clear (`name == nil`) the company for a meeting — the manual dashboard fix (P1).
    public func updateCompany(id: String, name: String?) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE meeting SET company = ? WHERE id = ?", arguments: [name, id])
        }
    }
```

And add `source` to the `Company` struct in `ContextPackage.swift` (after `matched`):

```swift
    public struct Company: Decodable, Sendable {
        public let name: String?
        public let sevantaDealId: String?
        public let dealigenceId: String?
        public let matched: Bool
        public let source: String?
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter MeetingStoreTests`
Expected: PASS (all MeetingStore tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/INMeetingsCore/Store/MeetingStore.swift Sources/INMeetingsCore/Store/ContextPackage.swift Tests/INMeetingsCoreTests/MeetingStoreTests.swift
git commit -m "feat(core): MeetingStore.updateCompany + Company.source decoding"
```

---

### Task 4: `CompanyEditor` — single-field metadata.json rewrite + SQLite

**Files:**
- Create: `Sources/INMeetingsCore/Store/CompanyEditor.swift`
- Create: `Tests/INMeetingsCoreTests/CompanyEditorTests.swift`

- [ ] **Step 1: Write the failing test** — create `Tests/INMeetingsCoreTests/CompanyEditorTests.swift`:

```swift
import XCTest
@testable import INMeetingsCore

final class CompanyEditorTests: XCTestCase {
    private var goldenDir: URL {
        URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "schema/fixtures/golden-package")
    }

    /// Copy the golden package to a temp dir so we can mutate its metadata.json.
    private func tempPackage() throws -> URL {
        let dst = FileManager.default.temporaryDirectory.appending(path: "ce-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: goldenDir, to: dst)
        return dst
    }

    func testSetCompanyRewritesMetadataAndIndex() throws {
        let dir = try tempPackage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try MeetingStore()
        let rec = try store.indexPackage(at: dir)

        _ = try CompanyEditor(store: store).setCompany("Acme AI", for: rec)

        // SQLite updated
        XCTAssertEqual(try store.meeting(id: rec.id)?.company, "Acme AI")
        // metadata.json updated, other keys preserved
        let data = try Data(contentsOf: dir.appending(path: "metadata.json"))
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let company = root["company"] as! [String: Any]
        XCTAssertEqual(company["name"] as? String, "Acme AI")
        XCTAssertEqual(company["source"] as? String, "user")
        XCTAssertEqual((root["meeting"] as? [String: Any])?["type"] as? String, "call")  // untouched
    }

    func testClearCompanyWritesNull() throws {
        let dir = try tempPackage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try MeetingStore()
        let rec = try store.indexPackage(at: dir)

        _ = try CompanyEditor(store: store).setCompany("   ", for: rec)  // blank → clear

        XCTAssertNil(try store.meeting(id: rec.id)?.company)
        let root = try JSONSerialization.jsonObject(
            with: Data(contentsOf: dir.appending(path: "metadata.json"))) as! [String: Any]
        XCTAssertTrue((root["company"] as! [String: Any])["name"] is NSNull)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter CompanyEditorTests`
Expected: FAIL (no `CompanyEditor` type).

- [ ] **Step 3: Implement** — create `Sources/INMeetingsCore/Store/CompanyEditor.swift`:

```swift
import Foundation

public enum CompanyEditorError: Error { case malformedMetadata }

/// Applies a user company edit to a meeting: rewrites `metadata.json`'s `company` object (single field,
/// preserving every other key) and updates the SQLite index. Returns the new `metadata.json` bytes so the
/// caller (which owns the Drive token + location) can re-upload them.
///
/// A deliberate, documented exception to "Python is the single writer of the package" (ADR-009): this is
/// a serialized, post-pipeline, one-field user edit — not concurrent assembly. Keys are re-serialized in
/// sorted order (deterministic across edits); `metadata.json` is machine-read, so order does not matter.
public struct CompanyEditor {
    private let store: MeetingStore
    public init(store: MeetingStore) { self.store = store }

    @discardableResult
    public func setCompany(_ rawName: String?, for meeting: MeetingRecord) throws -> Data {
        let trimmed = rawName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String? = (trimmed?.isEmpty == false) ? trimmed : nil

        let url = URL(fileURLWithPath: meeting.folderPath).appendingPathComponent("metadata.json")
        let data = try Data(contentsOf: url)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CompanyEditorError.malformedMetadata
        }
        var company = (root["company"] as? [String: Any]) ?? [:]
        company["name"] = name ?? NSNull()
        company["source"] = "user"
        if company["matched"] == nil { company["matched"] = false }
        root["company"] = company

        let newData = try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try newData.write(to: url, options: .atomic)

        try store.updateCompany(id: meeting.id, name: name)
        return newData
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter CompanyEditorTests`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/INMeetingsCore/Store/CompanyEditor.swift Tests/INMeetingsCoreTests/CompanyEditorTests.swift
git commit -m "feat(core): CompanyEditor — single-field metadata.json rewrite + index update"
```

---

### Task 5: Inline-editable company in the dashboard (local + disk persistence)

**Files:**
- Modify: `Apps/INMeetings/INMeetings/Dashboard/RecordingStore.swift`
- Modify: `Apps/INMeetings/INMeetings/Dashboard/MeetingDetailView.swift:24-38` (the `header`)

*No app-target unit test bundle — verified by build + manual run.*

- [ ] **Step 1: Add `setCompany` to `RecordingStore`** — inside `RecordingStore` (after `load()`):

```swift
    /// Apply a manual company edit: rewrite metadata.json + index (CompanyEditor), then refresh the list.
    /// (Drive re-upload is wired in Task 6.)
    func setCompany(_ name: String?, for meeting: MeetingRecord) {
        guard let store else { return }
        do {
            _ = try CompanyEditor(store: store).setCompany(name, for: meeting)
            load()
        } catch {
            NSLog("setCompany failed: \(error)")
        }
    }
```

- [ ] **Step 2: Make the company inline-editable** — in `MeetingDetailView`, add edit state (top of the struct, after `currentTime`):

```swift
    @State private var isEditingCompany = false
    @State private var draftCompany = ""
```

Replace the company `Text` in `header` (the `Text(meeting.company?.isEmpty == false ? ...)` line) with:

```swift
                if isEditingCompany {
                    TextField("Add company", text: $draftCompany)
                        .textFieldStyle(.roundedBorder).font(.title2.weight(.semibold))
                        .frame(maxWidth: 280)
                        .onSubmit { commitCompany() }
                } else {
                    Button {
                        draftCompany = meeting.company ?? ""; isEditingCompany = true
                    } label: {
                        Text(meeting.company?.isEmpty == false ? meeting.company! : "Add company")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(meeting.company?.isEmpty == false ? .primary : .secondary)
                    }.buttonStyle(.plain)
                }
```

Add these methods to `MeetingDetailView` (next to `copyTranscript`):

```swift
    private func commitCompany() {
        isEditingCompany = false
        store.setCompany(draftCompany, for: meeting)
    }
```

- [ ] **Step 3: Build**

Run: `make build-mac`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Manual verify**

Run: `make run-mac` → open the dashboard → pick a meeting.
Expected: the company is a button; click it → text field seeded with the current name; type "Test Co" + Enter → header shows "Test Co"; the row in the list shows it; **relaunch the app** → still "Test Co"; inspect `metadata.json` in the meeting folder → `company.name` = "Test Co", `company.source` = "user". A meeting under "Needs linking" shows "Add company" and assigning one removes it from that bucket.

- [ ] **Step 5: Commit**

```bash
git add Apps/INMeetings/INMeetings/Dashboard/RecordingStore.swift Apps/INMeetings/INMeetings/Dashboard/MeetingDetailView.swift
git commit -m "feat(app): inline-editable company in the meeting detail header"
```

---

### Task 6: Drive re-upload of the edited metadata.json

**Files:**
- Modify: `Sources/INMeetingsCore/Drive/DriveClient.swift` (new `fileQuery` + `uploadOrReplaceFile`)
- Modify: `Sources/INMeetingsCore/Drive/DriveSync.swift` (add `uploadOrReplaceFile` to `DriveUploading`)
- Modify: `Tests/INMeetingsCoreTests/DriveSyncTests.swift` (FakeUploader stub) + `DriveClientTests.swift` (request test)
- Modify: `Apps/INMeetings/INMeetings/DriveAuth.swift` (`reuploadMetadata`)
- Modify: `Apps/INMeetings/INMeetings/Dashboard/DashboardWindow.swift` + `RecordingStore.swift` (thread `DriveAuth`)

- [ ] **Step 1: Write the failing client request test** — append to `Tests/INMeetingsCoreTests/DriveClientTests.swift`:

```swift
    func testFileQueryEscapesAndScopesToParent() {
        let q = DriveClient.fileQuery(name: "metadata.json", parentID: "FOLDER1")
        XCTAssertTrue(q.contains("name = 'metadata.json'"))
        XCTAssertTrue(q.contains("'FOLDER1' in parents"))
        XCTAssertTrue(q.contains("trashed = false"))
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter DriveClientTests/testFileQueryEscapesAndScopesToParent`
Expected: FAIL (no `fileQuery`).

- [ ] **Step 3: Implement the client primitive** — in `DriveClient.swift`, add the `fileQuery` helper next to `folderQuery`:

```swift
    /// The `q` to find a non-trashed file by exact name under a parent (any mime). Escapes `\` then `'`.
    static func fileQuery(name: String, parentID: String) -> String {
        let escaped = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return "name = '\(escaped)' and '\(parentID)' in parents and trashed = false"
    }
```

And add the upsert method (after `uploadFile`):

```swift
    /// Update an existing file's content by (name, parent), or create it if absent — avoids the duplicate
    /// that a plain `uploadFile` would make. Used to re-push an edited metadata.json. Returns the file id.
    @discardableResult
    public func uploadOrReplaceFile(name: String, mimeType: String, data: Data,
                                    parentID: String, driveId: String?) async throws -> String {
        var search = URLComponents(url: Self.apiBase.appendingPathComponent("files"),
                                   resolvingAgainstBaseURL: false)!
        var query = [
            URLQueryItem(name: "q", value: Self.fileQuery(name: name, parentID: parentID)),
            URLQueryItem(name: "fields", value: "files(id,name)"),
            URLQueryItem(name: "supportsAllDrives", value: "true"),
            URLQueryItem(name: "includeItemsFromAllDrives", value: "true"),
        ]
        if let driveId {
            query.append(URLQueryItem(name: "corpora", value: "drive"))
            query.append(URLQueryItem(name: "driveId", value: driveId))
        }
        search.queryItems = query
        let (found, _) = try await send(search.url!, method: "GET")
        if let existing = try JSONDecoder().decode(FileListResponse.self, from: found).files.first {
            var update = URLComponents(
                url: Self.uploadBase.appendingPathComponent("files/\(existing.id)"),
                resolvingAgainstBaseURL: false)!
            update.queryItems = [
                URLQueryItem(name: "uploadType", value: "media"),
                URLQueryItem(name: "supportsAllDrives", value: "true"),
                URLQueryItem(name: "fields", value: "id"),
            ]
            let (resp, _) = try await send(update.url!, method: "PATCH", contentType: mimeType, body: data)
            return try JSONDecoder().decode(IDOnly.self, from: resp).id
        }
        return try await uploadFile(name: name, mimeType: mimeType, data: data,
                                    parentID: parentID, driveId: driveId)
    }
```

Add it to the `DriveUploading` protocol in `DriveSync.swift`:

```swift
    func uploadOrReplaceFile(name: String, mimeType: String, data: Data, parentID: String, driveId: String?) async throws -> String
```

- [ ] **Step 4: Keep the fake compiling** — add to `FakeUploader` in `DriveSyncTests.swift`:

```swift
    func uploadOrReplaceFile(name: String, mimeType: String, data: Data, parentID: String, driveId: String?) async throws -> String {
        "replaced-\(name)"
    }
```

- [ ] **Step 5: Run the tests**

Run: `swift test --filter DriveClientTests && swift test --filter DriveSyncTests`
Expected: PASS.

- [ ] **Step 6: Add the app-layer re-upload to `DriveAuth`** — add to `DriveAuth`:

```swift
    /// Best-effort re-push of an edited metadata.json to a meeting's existing Drive folder (P1 rename).
    func reuploadMetadata(meetingFolderID: String, data: Data) async {
        guard let location else { return }
        _ = try? await client.uploadOrReplaceFile(
            name: "metadata.json", mimeType: "application/json",
            data: data, parentID: meetingFolderID, driveId: location.driveID)
    }
```

- [ ] **Step 7: Thread `DriveAuth` into the dashboard** — in `DashboardWindow.swift`, replace the `storeModel` line + add an init:

```swift
struct DashboardWindow: View {
    let drive: DriveAuth
    @State private var storeModel: RecordingStore
    init(drive: DriveAuth) {
        self.drive = drive
        _storeModel = State(initialValue: RecordingStore(drive: drive))
    }
```

In `INMeetingsApp.swift:54`, pass it: `DashboardWindow(drive: drive)`.

In `RecordingStore.swift`, accept + store the dependency and use it in `setCompany`:

```swift
    private let drive: DriveAuth?
    init(store: MeetingStore? = try? MeetingStore(url: MeetingStore.defaultURL), drive: DriveAuth? = nil) {
        self.store = store
        self.drive = drive
        load()
    }
```

and extend `setCompany` to re-upload after a successful edit:

```swift
    func setCompany(_ name: String?, for meeting: MeetingRecord) {
        guard let store else { return }
        do {
            let data = try CompanyEditor(store: store).setCompany(name, for: meeting)
            load()
            if let drive, drive.isConnected, let folderID = meeting.driveFolderId {
                Task { await drive.reuploadMetadata(meetingFolderID: folderID, data: data) }
            }
        } catch {
            NSLog("setCompany failed: \(error)")
        }
    }
```

- [ ] **Step 8: Build**

Run: `make build-mac`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 9: Manual verify (needs a Drive-connected, already-synced meeting)**

Run: `make run-mac` → rename the company of a meeting whose `driveFolderId` is set (already synced).
Expected: locally updates as in Task 5; within a few seconds the meeting's **Drive** `metadata.json` reflects the new `company.name`/`source:"user"` (open it in Drive), and **no duplicate** `metadata.json` appears in the folder. Renaming an un-synced meeting does nothing to Drive (uploads correctly on its first sync).

- [ ] **Step 10: Commit**

```bash
git add Sources/INMeetingsCore/Drive/DriveClient.swift Sources/INMeetingsCore/Drive/DriveSync.swift Tests/INMeetingsCoreTests/DriveClientTests.swift Tests/INMeetingsCoreTests/DriveSyncTests.swift Apps/INMeetings/INMeetings/DriveAuth.swift Apps/INMeetings/INMeetings/Dashboard/DashboardWindow.swift Apps/INMeetings/INMeetings/Dashboard/RecordingStore.swift
git commit -m "feat: re-upload edited metadata.json to Drive on company rename"
```

---

## Self-Review

**1. Spec coverage:**
- Title fallback + `source` → Task 1. ✅
- Schema/fixture `source` → Task 2. ✅
- `updateCompany` + `Company.source` → Task 3. ✅
- `CompanyEditor` (metadata + SQLite) → Task 4. ✅
- Inline edit UI / Needs-linking assign / empty-clears → Task 5. ✅
- Drive re-upload (no folder move) → Task 6. ✅
- "Disable while processing" → intentionally dropped (indexed meetings are past the pipeline; noted in spec/plan). ✅
- Edge cases: re-index preserves edit (metadata.json is the source, Task 4); not-synced (Task 6 Step 9); Drive failure non-blocking (`try?` in `reuploadMetadata`). ✅

**2. Placeholder scan:** none — every code step is complete; the only conditional ("add `import re` if missing") is a precise instruction.

**3. Type consistency:** `setCompany(_:for:) -> Data` (Task 4) is called discarding the result in Task 5 and using it in Task 6; `uploadOrReplaceFile(name:mimeType:data:parentID:driveId:)` identical in client, protocol, fake, and `DriveAuth` call; `RecordingStore.setCompany(_:for:)` signature stable across Tasks 5–6 (Task 6 adds the Drive branch only); `CompanyEditor(store:)` matches its tests; `fileQuery(name:parentID:)` matches its test and call site.

## Out of scope (per spec)
Transcript NER · Drive folder rename/move · meeting-title editing · CRM `matched:true` · autocomplete/bulk.
