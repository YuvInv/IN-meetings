import Foundation

/// Sets a diarized speaker's display name in a meeting's `transcript.json` — the dashboard "name this
/// speaker" action (assign a diarized "Speaker 1" → "Gil", etc.). Speaker names aren't in the SQLite
/// index (they live only in the package), so this rewrites `transcript.json` in place and returns the new
/// bytes for Drive re-upload. Additive: `speakers[].name`/`email` are already in the frozen schema.
///
/// True automatic naming would need voice identification (which diarized voice is Gil vs Shirley); until
/// then names are a one-tap manual assignment from the meeting's attendees (or free text).
public enum SpeakerEditor {
    /// Set (or clear, when `name` is nil/blank) the display name for `speakerId` in `folder`'s
    /// `transcript.json`. Returns the rewritten file bytes. Throws if the transcript can't be read/written.
    @discardableResult
    public static func setName(_ name: String?, email: String? = nil,
                              speakerId: String, in folder: URL) throws -> Data {
        let url = folder.appendingPathComponent("transcript.json")
        guard var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              var speakers = json["speakers"] as? [[String: Any]] else {
            throw NSError(domain: "SpeakerEditor", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "transcript.json has no speakers array"])
        }
        let clean = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        for i in speakers.indices where speakers[i]["id"] as? String == speakerId {
            if let clean, !clean.isEmpty {
                speakers[i]["name"] = clean
                if let email, !email.isEmpty { speakers[i]["email"] = email }
            } else {
                speakers[i].removeValue(forKey: "name")
            }
        }
        json["speakers"] = speakers
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        return data
    }
}
