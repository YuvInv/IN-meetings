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
